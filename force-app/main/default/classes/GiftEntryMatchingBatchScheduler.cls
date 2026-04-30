/**
 * GiftEntryMatchingBatchScheduler
 *
 * Schedulable wrapper for GiftEntryMatchingBatch.
 *
 * Schedule via Setup → Apex Classes → Schedule Apex, or anonymous Apex:
 *
 *   // Run nightly at 2:00 AM for a specific GiftBatch
 *   System.schedule(
 *       'Gift Entry Matching - Nightly',
 *       '0 0 2 * * ?',
 *       new GiftEntryMatchingBatchScheduler(giftBatchId)
 *   );
 *
 *   // Run immediately
 *   Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), 50);
 */
public with sharing class GiftEntryMatchingBatchScheduler implements Schedulable {

    private final Id giftBatchId;
    private final Integer batchSize;

    /**
     * @param giftBatchId  Id of the GiftBatch__c / GiftBatch record to process.
     * @param batchSize    Number of GiftEntry records per chunk (default 50).
     */
    public GiftEntryMatchingBatchScheduler(Id giftBatchId, Integer batchSize) {
        this.giftBatchId = giftBatchId;
        this.batchSize   = batchSize != null ? batchSize : 50;
    }

    public GiftEntryMatchingBatchScheduler(Id giftBatchId) {
        this(giftBatchId, 50);
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), batchSize);
    }
}
