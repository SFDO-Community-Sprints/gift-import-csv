/**
 * GiftEntryMatchingRuleEvaluator
 *
 * Responsible for token substitution in SOQL WHERE clauses and executing
 * dynamic SOQL to find a matching record for a given GiftEntry field.
 *
 * Token syntax: {!GiftEntry.FieldApiName}
 * Example rule WHERE clause:
 *   PersonEmail = '{!GiftEntry.Email__c}' AND IsPersonAccount = true
 *
 * The evaluator iterates active rules (sorted by Priority__c ASC) for a given
 * TargetField and stops as soon as a match is found (first-match-wins).
 */
public with sharing class GiftEntryMatchingRuleEvaluator {

    /**
     * Token regex: matches {!GiftEntry.SomeField} or {!GiftEntry.SomeField+10}
     * or {!GiftEntry.SomeField-10}.
     * Group 1 = field API name, Group 2 = optional day offset (e.g. "+10" or "-10").
     */
    private static final Pattern TOKEN_PATTERN =
        Pattern.compile('\\{!GiftEntry\\.([A-Za-z0-9_]+)([+-]\\d+)?\\}');

    /**
     * Holds the result of a rule evaluation for one GiftEntry / one TargetField.
     */
    public class MatchResult {
        /** Id of the matched record, or null if no match found. */
        public Id matchedId { get; private set; }
        /** Weight of the rule that produced this match (0.0–1.0). */
        public Decimal matchScore { get; private set; }
        /** DeveloperName of the winning rule. */
        public String winningRuleName { get; private set; }

        public MatchResult(Id matchedId, Decimal matchScore, String winningRuleName) {
            this.matchedId     = matchedId;
            this.matchScore    = matchScore;
            this.winningRuleName = winningRuleName;
        }
    }

    /**
     * Evaluates all active rules for a given TargetField against a single GiftEntry
     * record (already in memory). Rules are evaluated in Priority__c ASC order;
     * the first rule that returns a result wins.
     *
     * @param entry       GiftEntry SObject with all needed fields populated.
     * @param rules       Ordered list of active GiftEntryMatchingRule__mdt records
     *                    for the target field (Priority__c ASC).
     * @param entryFields Map of field API name → value for the entry (pre-built for
     *                    performance so we only call .get() instead of reflection).
     * @return MatchResult with the matched Id and score, or null if no match.
     */
    public static MatchResult evaluate(
        SObject entry,
        List<GiftEntryMatchingRule__mdt> rules,
        Map<String, Object> entryFields
    ) {
        for (GiftEntryMatchingRule__mdt rule : rules) {
            // Build the dynamic SOQL for this rule
            String whereClause = substituteTokens(rule.SoqlWhereClause__c, entryFields);

            // Skip if token substitution produced a null/blank value (no data to match on)
            if (whereClause == null) {
                System.debug(LoggingLevel.WARN,
                    'GiftEntryMatchingRuleEvaluator: rule [' + rule.DeveloperName
                    + '] skipped — one or more token fields are null on this GiftEntry.');
                continue;
            }

            String soql = 'SELECT Id FROM ' + String.escapeSingleQuotes(rule.TargetObject__c)
                        + ' WHERE ' + whereClause
                        + ' LIMIT 1';

            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingRuleEvaluator: rule [' + rule.DeveloperName
                + '] executing SOQL: ' + soql);

            List<SObject> results;
            try {
                results = Database.query(soql);
            } catch (QueryException qe) {
                // Log and skip a badly-formed rule rather than crashing the whole batch
                System.debug(LoggingLevel.ERROR,
                    'GiftEntryMatchingRuleEvaluator: rule [' + rule.DeveloperName
                    + '] produced invalid SOQL: ' + soql + ' | Error: ' + qe.getMessage());
                continue;
            }

            if (!results.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'GiftEntryMatchingRuleEvaluator: rule [' + rule.DeveloperName
                    + '] matched record Id=' + results[0].Id
                    + ' (score=' + rule.Weight__c + ')');
                return new MatchResult(
                    results[0].Id,
                    rule.Weight__c != null ? rule.Weight__c : 0,
                    rule.DeveloperName
                );
            }

            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingRuleEvaluator: rule [' + rule.DeveloperName
                + '] returned no results.');
        }

        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingRuleEvaluator: no match found across all rules for this field.');
        return null; // No match found across all rules for this field
    }

    /**
     * Replaces all {!GiftEntry.FieldName} (and {!GiftEntry.FieldName±N}) tokens
     * in the WHERE clause template with the actual values from the GiftEntry record.
     *
     * Supported token forms:
     *   {!GiftEntry.Email}              → substitutes the raw field value
     *   {!GiftEntry.GiftReceivedDate-10} → Date field value minus 10 days
     *   {!GiftEntry.GiftReceivedDate+10} → Date field value plus 10 days
     *
     * Rules:
     *   - String/Id values are single-quoted and escaped automatically.
     *   - Date/DateTime values are formatted as SOQL literals (no surrounding quotes).
     *   - Day offsets are only applied to Date and DateTime field values.
     *   - Null-valued tokens cause the method to return null (rule is skipped).
     */
    @TestVisible
    private static String substituteTokens(String template, Map<String, Object> entryFields) {
        if (String.isBlank(template)) {
            return null;
        }

        String result = template;
        Matcher m = TOKEN_PATTERN.matcher(template);

        while (m.find()) {
            String fieldName  = m.group(1);           // e.g. 'GiftReceivedDate'
            String offsetStr  = m.group(2);           // e.g. '-10', '+10', or null
            Object fieldValue = entryFields.get(fieldName);

            if (fieldValue == null) {
                System.debug(LoggingLevel.WARN,
                    'GiftEntryMatchingRuleEvaluator.substituteTokens: token {!GiftEntry.'
                    + fieldName + (offsetStr != null ? offsetStr : '') + '} resolved to NULL. '
                    + 'Check that this field API name exists on GiftEntry and is populated. '
                    + 'Available fields on this entry: ' + entryFields.keySet());
                return null;
            }

            // Apply day offset if present (only meaningful for Date / DateTime fields)
            if (offsetStr != null) {
                // Strip leading '+' so Integer.valueOf handles both '+10' and '-10'
                Integer days = Integer.valueOf(offsetStr.replace('+', ''));
                if (fieldValue instanceof Date) {
                    fieldValue = ((Date) fieldValue).addDays(days);
                } else if (fieldValue instanceof DateTime) {
                    fieldValue = ((DateTime) fieldValue).addDays(days);
                }
                // For non-date types the offset is silently ignored
            }

            System.debug(LoggingLevel.INFO,
                'GiftEntryMatchingRuleEvaluator.substituteTokens: token {!GiftEntry.'
                + fieldName + (offsetStr != null ? offsetStr : '') + '} → ' + fieldValue);

            String soqlLiteral = toSoqlLiteral(fieldValue);
            result = result.replace(m.group(0), soqlLiteral);
        }

        return result;
    }

    /**
     * Converts an Apex value to a SOQL-safe literal string (unquoted for
     * non-string types; single-quoted and escaped for strings/IDs).
     */
    private static String toSoqlLiteral(Object value) {
        if (value instanceof String) {
            return '\'' + String.escapeSingleQuotes((String) value) + '\'';
        }
        if (value instanceof Id) {
            return '\'' + String.escapeSingleQuotes(String.valueOf(value)) + '\'';
        }
        if (value instanceof Date) {
            Date d = (Date) value;
            return String.valueOf(d.year())
                + '-' + String.valueOf(d.month()).leftPad(2, '0')
                + '-' + String.valueOf(d.day()).leftPad(2, '0');
        }
        if (value instanceof DateTime) {
            DateTime dt = (DateTime) value;
            return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (value instanceof Boolean) {
            return ((Boolean) value) ? 'true' : 'false';
        }
        // Numbers, Decimals, etc.
        return String.valueOf(value);
    }

    /**
     * Builds a field-value map from a GiftEntry SObject for use in token substitution.
     * Includes all populated fields on the record.
     *
     * @param entry A GiftEntry SObject with all required fields queried.
     * @return Map of field API name → field value.
     */
    public static Map<String, Object> buildFieldMap(SObject entry) {
        Map<String, Object> fieldMap = new Map<String, Object>();
        Map<String, Object> populatedFields = entry.getPopulatedFieldsAsMap();
        for (String fieldName : populatedFields.keySet()) {
            fieldMap.put(fieldName, populatedFields.get(fieldName));
        }
        System.debug(LoggingLevel.INFO,
            'GiftEntryMatchingRuleEvaluator.buildFieldMap: GiftEntry populated field keys = '
            + fieldMap.keySet());
        return fieldMap;
    }

    /**
     * Parses a SOQL WHERE clause template and returns every GiftEntry field name
     * referenced by a {!GiftEntry.FieldName} token.
     * Used by GiftEntryMatchingBatch to auto-build the SELECT field list.
     *
     * @param whereClause The raw WHERE clause template from a CMT rule.
     * @return Set of field API names (without the {!GiftEntry.} wrapper).
     */
    public static Set<String> extractTokenFields(String whereClause) {
        Set<String> fields = new Set<String>();
        if (String.isBlank(whereClause)) {
            return fields;
        }
        Matcher m = TOKEN_PATTERN.matcher(whereClause);
        while (m.find()) {
            fields.add(m.group(1));
        }
        return fields;
    }
}
