/**
 * GiftEntryMatchingController
 *
 * AuraEnabled Apex controller invoked by the giftEntryMatchingAction LWC.
 * Enqueues matching and employer matching batches for a given GiftBatch record.
 */
public with sharing class GiftEntryMatchingController {

    /**
     * Enqueues the lookup-field matching batch for the given GiftBatch Id.
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

    /**
     * Enqueues the Benevity employer matching gift batch for the given GiftBatch Id.
     * Reads configuration from BenevityMatchingSettings__c (Hierarchy Custom Setting).
     *
     * @param giftBatchId  Id of the GiftBatch record to process.
     * @param batchSize    Number of GiftEntry records per chunk (default 50).
     * @return             The AsyncApexJob Id of the enqueued batch.
     */
    @AuraEnabled
    public static Id runEmployerMatchingBatch(Id giftBatchId, Integer batchSize) {
        if (giftBatchId == null) {
            throw new AuraHandledException('GiftBatch Id is required.');
        }

        Integer size = (batchSize != null && batchSize > 0) ? batchSize : 50;

        try {
            return Database.executeBatch(
                new BenevityEmployerMatchingBatch(giftBatchId), size
            );
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to start employer matching batch: ' + e.getMessage()
            );
        }
    }
}
