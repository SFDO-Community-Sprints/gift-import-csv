/**
 * GiftEntryMatchingController
 *
 * AuraEnabled Apex controller invoked by the giftEntryMatchingAction LWC.
 * Enqueues the GiftEntryMatchingBatch for a given GiftBatch record.
 */
public with sharing class GiftEntryMatchingController {

    /**
     * Enqueues the matching batch for the given GiftBatch Id.
     *
     * @param giftBatchId  Id of the GiftBatch record to process.
     * @param batchSize    Number of GiftEntry records per chunk (default 50).
     * @return             The AsyncApexJob Id of the enqueued batch.
     */
    @AuraEnabled
    public static Id runMatchingBatch(Id giftBatchId, Integer batchSize) {
        if (giftBatchId == null) {
            throw new AuraHandledException('GiftBatch Id is required.');
        }

        Integer size = (batchSize != null && batchSize > 0) ? batchSize : 50;

        try {
            return Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), size);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to start matching batch: ' + e.getMessage()
            );
        }
    }
}
