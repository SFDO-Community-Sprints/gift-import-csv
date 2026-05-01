/**
 * BenevityEmployerMatchingBatch
 *
 * Processes GiftEntry records from a Benevity import and creates a separate
 * GiftEntry record for each employer whose matching gift amount is present.
 *
 * Behaviour is entirely driven by BenevityMatchingSettings__c (Hierarchy Custom Setting):
 *
 *   IsActive__c               — master on/off switch
 *   EmployeeGiftCondition__c  — SOQL WHERE clause that selects eligible employee entries
 *                               (e.g. "GEM_MatchAmount__c > 0 AND GEM_MatchingGiftCreated__c = false")
 *   EmployerIdPath__c         — SOQL dot-notation path to the employer Account Id on the
 *                               employee donor's Account record
 *                               (e.g. "Donor.Employer__c")
 *                               Supports multi-level traversal: "Donor.Parent.Employer__c"
 *   FieldsToCopy__c           — Semicolon-separated GiftEntry field API names to clone
 *                               onto the new employer gift entry
 *                               (e.g. "GiftBatchId;GiftReceivedDate;CurrencyIsoCode")
 *   MatchAmountField__c       — API name of the GiftEntry field holding the employer
 *                               match amount (e.g. "GEM_MatchAmount__c")
 *   MatchFlagField__c         — API name of a boolean GiftEntry field set to true after
 *                               the employer gift is created (e.g. "GEM_MatchingGiftCreated__c")
 *
 * For each eligible employee GiftEntry the batch will:
 *   1. Resolve the employer Account Id by traversing EmployerIdPath__c.
 *   2. Create a new GiftEntry cloning FieldsToCopy__c values.
 *   3. Set GiftAmount = MatchAmountField__c value, DonorId = employer Account Id.
 *   4. Set MatchFlagField__c = true on the original entry to prevent reprocessing.
 *
 * Usage:
 *   Id jobId = Database.executeBatch(new BenevityEmployerMatchingBatch(giftBatchId), 50);
 */
public with sharing class BenevityEmployerMatchingBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private final Id giftBatchId;

    // Stateful counters for the finish() summary log
    private Integer totalProcessed  = 0;
    private Integer totalCreated    = 0;
    private Integer totalSkipped    = 0;
    private Integer totalErrors     = 0;

    public BenevityEmployerMatchingBatch(Id giftBatchId) {
        this.giftBatchId = giftBatchId;
    }

    // ─── start() ─────────────────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        BenevityMatchingSettings__c s = BenevityMatchingSettings__c.getInstance();

        if (s == null || s.IsActive__c != true) {
            System.debug(LoggingLevel.WARN,
                'BenevityEmployerMatchingBatch: IsActive__c is false or settings not configured. '
                + 'No records will be processed.');
            // Return an empty QueryLocator by querying with an impossible condition
            return Database.getQueryLocator(
                'SELECT Id FROM GiftEntry WHERE Id = null LIMIT 0'
            );
        }

        // Build the SELECT field list dynamically
        Set<String> selectFields = buildSelectFields(s);

        String baseQuery =
            'SELECT ' + String.join(new List<String>(selectFields), ', ')
            + ' FROM GiftEntry'
            + ' WHERE GiftBatchId = \'' + String.escapeSingleQuotes(giftBatchId) + '\'';

        if (String.isNotBlank(s.EmployeeGiftCondition__c)) {
            baseQuery += ' AND (' + s.EmployeeGiftCondition__c + ')';
        }

        System.debug(LoggingLevel.INFO,
            'BenevityEmployerMatchingBatch.start() query: ' + baseQuery);

        return Database.getQueryLocator(baseQuery);
    }

    // ─── execute() ───────────────────────────────────────────────────────────

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        BenevityMatchingSettings__c s = BenevityMatchingSettings__c.getInstance();
        if (s == null || s.IsActive__c != true) {
            return;
        }

        // Parse the employer path: 'Donor.Parent.Employer__c'
        // → relationships = ['Donor', 'Parent'], employerFieldName = 'Employer__c'
        List<String> pathParts       = parseFieldPath(s.EmployerIdPath__c);
        String       employerField   = pathParts[pathParts.size() - 1];
        List<String> relationships   = new List<String>();
        for (Integer i = 0; i < pathParts.size() - 1; i++) {
            relationships.add(pathParts[i]);
        }

        // Parse the fields to copy
        List<String> fieldsToCopy = parseFieldList(s.FieldsToCopy__c);

        List<SObject> newEmployerGifts  = new List<SObject>();
        List<SObject> flagUpdates       = new List<SObject>();

        for (SObject entry : scope) {
            totalProcessed++;
            Id entryId = (Id) entry.get('Id');

            // ── 1. Validate match amount ──────────────────────────────────
            Decimal matchAmount = resolveMatchAmount(entry, s.MatchAmountField__c);
            if (matchAmount == null || matchAmount <= 0) {
                System.debug(LoggingLevel.INFO,
                    'BenevityEmployerMatchingBatch: entry ' + entryId
                    + ' skipped — match amount is null or zero.');
                totalSkipped++;
                continue;
            }

            // ── 2. Resolve employer Account Id ────────────────────────────
            Id employerId = resolveEmployerId(entry, relationships, employerField);
            if (employerId == null) {
                System.debug(LoggingLevel.WARN,
                    'BenevityEmployerMatchingBatch: entry ' + entryId
                    + ' skipped — could not resolve employer Id via path "'
                    + s.EmployerIdPath__c + '". Check that the path is correct and the '
                    + 'related Account has the employer field populated.');
                totalSkipped++;
                continue;
            }

            // ── 3. Build new employer GiftEntry ───────────────────────────
            SObject employerGift = buildEmployerGift(
                entry, employerId, matchAmount, fieldsToCopy
            );
            newEmployerGifts.add(employerGift);

            // ── 4. Prepare flag update on original entry ──────────────────
            if (String.isNotBlank(s.MatchFlagField__c)) {
                SObject flagUpdate = entry.getSObjectType().newSObject();
                flagUpdate.put('Id', entryId);
                flagUpdate.put(s.MatchFlagField__c, true);
                flagUpdates.add(flagUpdate);
            }
        }

        // ── DML ───────────────────────────────────────────────────────────
        if (!newEmployerGifts.isEmpty()) {
            List<Database.SaveResult> insertResults =
                Database.insert(newEmployerGifts, false);
            for (Database.SaveResult sr : insertResults) {
                if (sr.isSuccess()) {
                    totalCreated++;
                    System.debug(LoggingLevel.INFO,
                        'BenevityEmployerMatchingBatch: created employer gift Id=' + sr.getId());
                } else {
                    totalErrors++;
                    System.debug(LoggingLevel.ERROR,
                        'BenevityEmployerMatchingBatch: failed to create employer gift — '
                        + sr.getErrors());
                }
            }
        }

        if (!flagUpdates.isEmpty()) {
            List<Database.SaveResult> updateResults =
                Database.update(flagUpdates, false);
            for (Database.SaveResult sr : updateResults) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'BenevityEmployerMatchingBatch: failed to flag entry Id='
                        + sr.getId() + ' — ' + sr.getErrors());
                }
            }
        }
    }

    // ─── finish() ────────────────────────────────────────────────────────────

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'BenevityEmployerMatchingBatch complete. GiftBatchId=' + giftBatchId
            + ' | Processed='  + totalProcessed
            + ' | Created='    + totalCreated
            + ' | Skipped='    + totalSkipped
            + ' | Errors='     + totalErrors);
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    /**
     * Builds the complete set of field API names for the SELECT clause.
     * Always includes Id, DonorId, and the configured match amount / flag fields.
     * Also adds the employer path (for cross-object traversal) and all copy fields.
     */
    @TestVisible
    private static Set<String> buildSelectFields(BenevityMatchingSettings__c s) {
        Set<String> fields = new Set<String>{ 'Id', 'DonorId' };

        if (String.isNotBlank(s.MatchAmountField__c)) {
            fields.add(s.MatchAmountField__c.trim());
        }
        if (String.isNotBlank(s.MatchFlagField__c)) {
            fields.add(s.MatchFlagField__c.trim());
        }
        if (String.isNotBlank(s.EmployerIdPath__c)) {
            fields.add(s.EmployerIdPath__c.trim()); // cross-object, e.g. Donor.Employer__c
        }
        for (String f : parseFieldList(s.FieldsToCopy__c)) {
            fields.add(f);
        }

        return fields;
    }

    /**
     * Parses a semicolon-separated field list string into a trimmed List<String>.
     * Returns an empty list if the input is blank.
     */
    @TestVisible
    private static List<String> parseFieldList(String raw) {
        List<String> result = new List<String>();
        if (String.isBlank(raw)) {
            return result;
        }
        for (String token : raw.split(';')) {
            String trimmed = token.trim();
            if (String.isNotBlank(trimmed)) {
                result.add(trimmed);
            }
        }
        return result;
    }

    /**
     * Parses a dot-notation SOQL field path into its component parts.
     * e.g. 'Donor.Parent.Employer__c' → ['Donor', 'Parent', 'Employer__c']
     * Returns a list with a single element if there is no dot.
     */
    @TestVisible
    private static List<String> parseFieldPath(String path) {
        if (String.isBlank(path)) {
            return new List<String>{ '' };
        }
        List<String> parts = new List<String>();
        for (String p : path.trim().split('\\.')) {
            parts.add(p.trim());
        }
        return parts;
    }

    /**
     * Traverses the SObject relationship chain to resolve the employer Account Id.
     * e.g. relationships = ['Donor', 'Parent'], field = 'Employer__c'
     *      → entry.getSObject('Donor').getSObject('Parent').get('Employer__c')
     * Returns null if any step in the chain is null or if the field is not an Id.
     */
    @TestVisible
    private static Id resolveEmployerId(
        SObject entry,
        List<String> relationships,
        String employerField
    ) {
        SObject current = entry;
        for (String rel : relationships) {
            if (current == null) {
                return null;
            }
            current = current.getSObject(rel);
        }
        if (current == null) {
            return null;
        }
        Object val = current.get(employerField);
        try {
            return (Id) val;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'BenevityEmployerMatchingBatch.resolveEmployerId: field "'
                + employerField + '" could not be cast to Id. Value=' + val);
            return null;
        }
    }

    /**
     * Reads the match amount from the configured field on the GiftEntry.
     * Returns null if the field name is blank or the value cannot be cast to Decimal.
     */
    @TestVisible
    private static Decimal resolveMatchAmount(SObject entry, String matchAmountField) {
        if (String.isBlank(matchAmountField)) {
            return null;
        }
        try {
            return (Decimal) entry.get(matchAmountField.trim());
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'BenevityEmployerMatchingBatch.resolveMatchAmount: could not read "'
                + matchAmountField + '" as Decimal. Error: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Constructs the new employer GiftEntry SObject by:
     *   1. Copying all requested fields from the source entry.
     *   2. Overriding DonorId with the employer Account Id.
     *   3. Overriding GiftAmount with the match amount.
     * Fields that cannot be set (system fields, formula, etc.) are silently skipped
     * with a WARN log so a misconfigured FieldsToCopy__c never crashes the batch.
     */
    @TestVisible
    private static SObject buildEmployerGift(
        SObject sourceEntry,
        Id employerId,
        Decimal matchAmount,
        List<String> fieldsToCopy
    ) {
        SObject employerGift = sourceEntry.getSObjectType().newSObject();

        for (String fieldName : fieldsToCopy) {
            try {
                Object val = sourceEntry.get(fieldName);
                if (val != null) {
                    employerGift.put(fieldName, val);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'BenevityEmployerMatchingBatch.buildEmployerGift: could not copy field "'
                    + fieldName + '": ' + e.getMessage());
            }
        }

        // These always override whatever was copied
        employerGift.put('DonorId',     employerId);
        employerGift.put('GiftAmount',  matchAmount);

        return employerGift;
    }
}
