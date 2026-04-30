/**
 * GiftEntryMatchingBatch
 *
 * Processes GiftEntry records within a specific GiftBatch and pre-fills
 * the following lookup fields in strict priority order:
 *
 *   1. DonorId           → Account
 *   2. GiftCommitmentId  → GiftCommitment
 *   3. OutreachSourceCodeId → OutreachSourceCode
 *   4. CampaignId        → Campaign
 *   5. GiftDesignation1Id → GiftDesignation
 *   6. GiftDesignation2Id → GiftDesignation
 *   7. GiftDesignation3Id → GiftDesignation
 *
 * Matching rules are defined in the GiftEntryMatchingRule__mdt custom metadata type.
 * Rules within each field group are evaluated in Priority__c ASC order; the first
 * rule that returns a result wins and no further rules for that field are evaluated.
 *
 * GiftEntry records within a batch are processed in GiftReceivedDate ASC order so
 * that earlier gifts resolve their lookups first (important when later entries may
 * depend on data created/matched by earlier ones).
 *
 * Match scores (rule Weight__c) are stored on corresponding score fields for
 * auditability, even though any match is always accepted.
 *
 * Usage:
 *   Id batchJobId = Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), 50);
 *
 * Scheduling:
 *   System.schedule('Gift Entry Matching - Nightly', '0 0 2 * * ?',
 *       new GiftEntryMatchingBatchScheduler(giftBatchId));
 */
public with sharing class GiftEntryMatchingBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * All standard NPC GiftEntry field API names included in every query.
     * These cover the full set of out-of-the-box fields available for matching rules.
     */
    private static final Set<String> BASE_GIFT_ENTRY_FIELDS = new Set<String>{
        'Id', 'Name', 'GiftBatchId', 'GiftReceivedDate',
        // Donor identity
        'Salutation', 'FirstName', 'LastName', 'OrganizationName',
        'Email', 'HomePhone', 'MobilePhone',
        // Address
        'Street', 'City', 'State', 'PostalCode', 'Country',
        // Lookup fields (the ones we are trying to populate)
        'DonorId', 'GiftCommitmentId', 'OutreachSourceCodeId',
        'CampaignId', 'GiftDesignation1Id', 'GiftDesignation2Id', 'GiftDesignation3Id',
        // Gift amounts & designations
        'GiftAmount', 'DonorCoverAmount', 'TotalTransactionFeeAmount',
        'GiftDesignation1Amount', 'GiftDesignation2Amount', 'GiftDesignation3Amount',
        'GiftDesignation1Percent', 'GiftDesignation2Percent', 'GiftDesignation3Percent',
        'SoftCreditInformation',
        // Gift type & status
        'GiftType', 'GiftProcessingStatus', 'GiftProcessingResult',
        'IsNewRecurringGift', 'IsSetAsDefault',
        // Payment
        'PaymentMethod', 'PaymentIdentifier', 'Last4', 'ExpiryMonth', 'ExpiryYear',
        // Recurring / schedule
        'TransactionInterval', 'TransactionPeriod', 'TransactionDay',
        'EffectiveStartDate', 'ExpectedEndDate', 'CheckDate',
        // System / audit
        'CurrencyIsoCode', 'LastProcessedDateTime',
        'LastReferencedDate', 'LastViewedDate'
    };

    /**
     * Ordered list of GiftEntry lookup field API names.
     * Each field is resolved before the next so later fields can reference
     * values populated by earlier lookups (e.g. GiftCommitmentId can filter
     * on the already-resolved DonorId).
     */
    private static final List<String> ORDERED_LOOKUP_FIELDS = new List<String>{
        'DonorId',
        'GiftCommitmentId',
        'OutreachSourceCodeId',
        'CampaignId',
        'GiftDesignation1Id',
        'GiftDesignation2Id',
        'GiftDesignation3Id'
    };

    /**
     * Maps each lookup field to the name of the custom score field that records
     * the weight of the matching rule. These fields must be created on GiftEntry.
     */
    private static final Map<String, String> SCORE_FIELD_MAP = new Map<String, String>{
        'DonorId'              => 'GEM_DonorMatchScore__c',
        'GiftCommitmentId'     => 'GEM_GiftCommitmentMatchScore__c',
        'OutreachSourceCodeId' => 'GEM_OutreachSourceCodeMatchScore__c',
        'CampaignId'           => 'GEM_CampaignMatchScore__c',
        'GiftDesignation1Id'   => 'GEM_GiftDesignation1MatchScore__c',
        'GiftDesignation2Id'   => 'GEM_GiftDesignation2MatchScore__c',
        'GiftDesignation3Id'   => 'GEM_GiftDesignation3MatchScore__c'
    };

    // ─── Instance State ──────────────────────────────────────────────────────

    /** Id of the GiftBatch record whose GiftEntry records are being processed. */
    private final Id giftBatchId;

    /** Cached and grouped matching rules, loaded once and reused across all chunks. */
    private Map<String, List<GiftEntryMatchingRule__mdt>> rulesByField;

    /** Stateful counters for finish() summary. */
    private Integer totalProcessed = 0;
    private Integer totalUpdated   = 0;
    private Integer totalErrors    = 0;

    // ─── Constructor ─────────────────────────────────────────────────────────

    public GiftEntryMatchingBatch(Id giftBatchId) {
        this.giftBatchId = giftBatchId;
    }

    // ─── Database.Batchable ──────────────────────────────────────────────────

    /**
     * Returns all GiftEntry records for the batch, ordered by GiftReceivedDate ASC
     * so earlier gifts are resolved first within the same batch.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Load and cache all active matching rules, sorted by Priority ASC
        this.rulesByField = loadAndGroupRules();

        // Log how many rules were loaded per field so we can confirm CMT records deployed
        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingBatch.start: loaded rule groups for fields: ' + rulesByField.keySet()
            + ' | Total field groups with rules: ' + rulesByField.size());
        for (String field : ORDERED_LOOKUP_FIELDS) {
            List<GiftEntryMatchingRule__mdt> fieldRules = rulesByField.get(field);
            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingBatch.start: field [' + field + '] has '
                + (fieldRules != null ? fieldRules.size() : 0) + ' active rule(s).');
        }

        // Build the SELECT field list:
        //   1. Start with all standard NPC GiftEntry fields
        //   2. Add score fields
        //   3. Scan all active rule WHERE clauses for {!GiftEntry.X} tokens and
        //      automatically add any referenced fields not already in the list.
        //      This means admins can reference any GiftEntry field in a rule
        //      without touching code.
        Set<String> selectFields = new Set<String>(BASE_GIFT_ENTRY_FIELDS);

        // Add score fields
        selectFields.addAll(SCORE_FIELD_MAP.values());

        // Discover extra fields from rule tokens
        for (List<GiftEntryMatchingRule__mdt> rules : rulesByField.values()) {
            for (GiftEntryMatchingRule__mdt rule : rules) {
                Set<String> tokenFields =
                    GiftEntryMatchingRuleEvaluator.extractTokenFields(rule.SoqlWhereClause__c);
                selectFields.addAll(tokenFields);
            }
        }

        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingBatch.start: querying GiftEntry with fields: ' + selectFields);

        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
                    + ' FROM GiftEntry'
                    + ' WHERE GiftBatchId = :giftBatchId'
                    + ' ORDER BY GiftReceivedDate ASC NULLS LAST';

        return Database.getQueryLocator(soql);
    }

    /**
     * For each chunk of GiftEntry records, evaluates all matching rules
     * field-by-field in the defined priority order and bulk-updates results.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<GiftEntry> entries = (List<GiftEntry>) scope;
        List<GiftEntry> toUpdate = new List<GiftEntry>();

        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingBatch.execute: processing ' + entries.size() + ' GiftEntry record(s).');

        for (GiftEntry entry : entries) {
            Boolean changed = false;

            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingBatch.execute: processing GiftEntry Id=' + entry.Id);

            // Build the current field-value map for token substitution.
            // This is rebuilt after each field resolution so that later rules
            // can reference values written by earlier lookups.
            Map<String, Object> fieldMap = GiftEntryMatchingRuleEvaluator.buildFieldMap(entry);

            // Process fields in strict priority order
            for (String lookupField : ORDERED_LOOKUP_FIELDS) {
                // Skip if already populated — don't overwrite existing data
                if (entry.get(lookupField) != null) {
                    System.debug(LoggingLevel.INFO,
                        'GiftEntryMatchingBatch.execute: field [' + lookupField
                        + '] already populated (' + entry.get(lookupField) + ') — skipping.');
                    continue;
                }

                List<GiftEntryMatchingRule__mdt> rules = rulesByField.get(lookupField);
                if (rules == null || rules.isEmpty()) {
                    System.debug(LoggingLevel.WARN,
                        'GiftEntryMatchingBatch.execute: field [' + lookupField
                        + '] has no active matching rules — skipping.');
                    continue;
                }

                System.debug(LoggingLevel.INFO,
                    'GiftEntryMatchingBatch.execute: evaluating ' + rules.size()
                    + ' rule(s) for field [' + lookupField + ']...');

                GiftEntryMatchingRuleEvaluator.MatchResult result =
                    GiftEntryMatchingRuleEvaluator.evaluate(entry, rules, fieldMap);

                if (result != null && result.matchedId != null) {
                    // Set the lookup field
                    entry.put(lookupField, result.matchedId);

                    // Set the corresponding score field
                    String scoreField = SCORE_FIELD_MAP.get(lookupField);
                    if (String.isNotBlank(scoreField)) {
                        entry.put(scoreField, result.matchScore);
                    }

                    // Refresh the field map so subsequent fields can reference
                    // the newly resolved value (e.g. GiftCommitmentId can use DonorId)
                    fieldMap.put(lookupField, result.matchedId);
                    changed = true;
                } else {
                    System.debug(LoggingLevel.INFO,
                        'GiftEntryMatchingBatch.execute: no match found for field [' + lookupField + '].');
                }
            }

            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingBatch.execute: GiftEntry Id=' + entry.Id
                + ' — changed=' + changed);

            if (changed) {
                toUpdate.add(entry);
            }
        }

        totalProcessed += entries.size();

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    totalUpdated++;
                } else {
                    totalErrors++;
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'GiftEntryMatchingBatch update error on GiftEntry [' + sr.getId()
                            + ']: ' + err.getMessage() + ' | Fields: ' + err.getFields());
                    }
                }
            }
        }
    }

    /**
     * Logs a summary of the batch run to the debug log.
     * Extend this method to send email, create a Task, or fire a Platform Event.
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingBatch complete. '
            + 'GiftBatchId=' + giftBatchId
            + ' | Processed=' + totalProcessed
            + ' | Updated=' + totalUpdated
            + ' | Errors=' + totalErrors);
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    /**
     * Queries all active GiftEntryMatchingRule__mdt records, sorts them by
     * Priority__c ASC, and groups them by TargetField__c for O(1) lookup during
     * execute().
     */
    private Map<String, List<GiftEntryMatchingRule__mdt>> loadAndGroupRules() {
        List<GiftEntryMatchingRule__mdt> allRules = [
            SELECT DeveloperName, Label,
                   TargetField__c, TargetObject__c,
                   SoqlWhereClause__c, Priority__c, Weight__c
            FROM GiftEntryMatchingRule__mdt
            WHERE IsActive__c = true
            ORDER BY TargetField__c ASC, Priority__c ASC
        ];

        Map<String, List<GiftEntryMatchingRule__mdt>> grouped =
            new Map<String, List<GiftEntryMatchingRule__mdt>>();

        for (GiftEntryMatchingRule__mdt rule : allRules) {
            String field = rule.TargetField__c;
            if (!grouped.containsKey(field)) {
                grouped.put(field, new List<GiftEntryMatchingRule__mdt>());
            }
            grouped.get(field).add(rule);
        }

        return grouped;
    }
}
