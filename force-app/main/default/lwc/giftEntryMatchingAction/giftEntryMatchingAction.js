import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runMatchingBatch from '@salesforce/apex/GiftEntryMatchingController.runMatchingBatch';

const STATE = {
    IDLE: 'idle',
    RUNNING: 'running',
    SUCCESS: 'success',
    ERROR: 'error'
};

export default class GiftEntryMatchingAction extends LightningElement {

    /** Automatically bound to the GiftBatch record Id by the Quick Action. */
    @api recordId;

    @track state = STATE.IDLE;
    @track jobId;
    @track errorMessage;

    // ─── State Helpers ───────────────────────────────────────────────────────

    get isIdle()    { return this.state === STATE.IDLE; }
    get isRunning() { return this.state === STATE.RUNNING; }
    get isSuccess() { return this.state === STATE.SUCCESS; }
    get isError()   { return this.state === STATE.ERROR; }

    // ─── Handlers ────────────────────────────────────────────────────────────

    handleRun() {
        this.state = STATE.RUNNING;
        this.jobId = null;
        this.errorMessage = null;

        runMatchingBatch({ giftBatchId: this.recordId, batchSize: 50 })
            .then((jobId) => {
                this.jobId = jobId;
                this.state = STATE.SUCCESS;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Matching batch submitted',
                        message: 'Job ID: ' + jobId,
                        variant: 'success'
                    })
                );
            })
            .catch((error) => {
                this.errorMessage =
                    (error.body && error.body.message)
                        ? error.body.message
                        : 'An unexpected error occurred.';
                this.state = STATE.ERROR;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Failed to start matching batch',
                        message: this.errorMessage,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );
            });
    }

    handleReset() {
        this.state = STATE.IDLE;
        this.jobId = null;
        this.errorMessage = null;
    }
}
