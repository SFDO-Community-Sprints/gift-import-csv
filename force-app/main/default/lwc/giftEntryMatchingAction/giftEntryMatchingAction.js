import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runMatchingBatch         from '@salesforce/apex/GiftEntryMatchingController.runMatchingBatch';
import runEmployerMatchingBatch from '@salesforce/apex/GiftEntryMatchingController.runEmployerMatchingBatch';

const STATE = {
    IDLE:    'idle',
    RUNNING: 'running',
    SUCCESS: 'success',
    ERROR:   'error'
};

const ACTION = {
    MATCHING:          'matching',
    EMPLOYER_MATCHING: 'employerMatching'
};

export default class GiftEntryMatchingAction extends LightningElement {

    /** Automatically bound to the GiftBatch record Id by the Lightning record page. */
    @api recordId;

    @track state        = STATE.IDLE;
    @track activeAction = null;
    @track jobId;
    @track errorMessage;

    // ─── State Helpers ────────────────────────────────────────────────────────

    get isIdle()    { return this.state === STATE.IDLE; }
    get isRunning() { return this.state === STATE.RUNNING; }
    get isSuccess() { return this.state === STATE.SUCCESS; }
    get isError()   { return this.state === STATE.ERROR; }

    get runningLabel() {
        return this.activeAction === ACTION.EMPLOYER_MATCHING
            ? 'Creating employer matching gifts'
            : 'Submitting matching batch job';
    }

    get successLabel() {
        return this.activeAction === ACTION.EMPLOYER_MATCHING
            ? 'Employer matching gift batch submitted successfully.'
            : 'Matching batch job submitted successfully.';
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleRunMatching() {
        this._submitBatch(ACTION.MATCHING);
    }

    handleRunEmployerMatching() {
        this._submitBatch(ACTION.EMPLOYER_MATCHING);
    }

    handleReset() {
        this.state        = STATE.IDLE;
        this.activeAction = null;
        this.jobId        = null;
        this.errorMessage = null;
    }

    // ─── Private ──────────────────────────────────────────────────────────────

    _submitBatch(action) {
        this.state        = STATE.RUNNING;
        this.activeAction = action;
        this.jobId        = null;
        this.errorMessage = null;

        const apexMethod = action === ACTION.EMPLOYER_MATCHING
            ? runEmployerMatchingBatch
            : runMatchingBatch;

        apexMethod({ giftBatchId: this.recordId, batchSize: 50 })
            .then((jobId) => {
                this.jobId  = jobId;
                this.state  = STATE.SUCCESS;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title:   this.successLabel,
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
                        title:   'Batch submission failed',
                        message: this.errorMessage,
                        variant: 'error',
                        mode:    'sticky'
                    })
                );
            });
    }
}
