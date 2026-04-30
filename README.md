# NPC Gift Entry Matching

An Apex batch job for **Salesforce Nonprofit Cloud (NPC)** that automatically pre-fills lookup fields on `GiftEntry` records using configurable, SOQL-based matching rules defined in Custom Metadata.

---

## Overview

When gift entries are imported into a `GiftBatch`, key lookup fields are often left blank because the system doesn't know which existing records to associate them with. This solution solves that by running a configurable matching engine that evaluates rules against each `GiftEntry` and populates the following fields in strict priority order:

| Priority | Field | Target Object |
|---|---|---|
| 1 | `DonorId` | `Account` |
| 2 | `GiftCommitmentId` | `GiftCommitment` |
| 3 | `OutreachSourceCodeId` | `OutreachSourceCode` |
| 4 | `CampaignId` | `Campaign` |
| 5 | `GiftDesignation1Id` | `GiftDesignation` |
| 6 | `GiftDesignation2Id` | `GiftDesignation` |
| 7 | `GiftDesignation3Id` | `GiftDesignation` |

Fields are resolved **sequentially** — so a later lookup (e.g. `GiftCommitmentId`) can reference the value resolved by an earlier one (e.g. `DonorId`) in its matching rule.

---

## How It Works

### Matching Rules (`GiftEntryMatchingRule__mdt`)

Each rule is a Custom Metadata record with the following fields:

| Field | Description |
|---|---|
| `Label` | Human-readable name |
| `TargetField__c` | API name of the `GiftEntry` lookup field to populate (e.g. `DonorId`) |
| `TargetObject__c` | API name of the SObject to query (e.g. `Account`) |
| `SoqlWhereClause__c` | SOQL `WHERE` clause with `{!GiftEntry.FieldName}` tokens substituted at runtime |
| `Priority__c` | Execution order within the same field group — lower runs first |
| `Weight__c` | Match confidence score (0.0–1.0) stored on the entry for auditability |
| `IsActive__c` | Toggle rules on/off without deleting them |

### Token Syntax

Reference any `GiftEntry` field value in a rule's WHERE clause using:

```
{!GiftEntry.FieldApiName}
```

**Examples:**

```sql
-- Match Account by email
PersonEmail = '{!GiftEntry.Email}' AND IsPersonAccount = true

-- Match Account by first + last name
FirstName = '{!GiftEntry.FirstName}' AND LastName = '{!GiftEntry.LastName}' AND IsPersonAccount = true

-- Match GiftCommitment using already-resolved DonorId (from step 1)
DonorId = '{!GiftEntry.DonorId}' AND Status = 'Active'
```

> **Note:** If a token references a field that is `null` on the `GiftEntry`, the rule is skipped and the next rule in priority order is evaluated.

### First-Match-Wins

Rules for the same `TargetField__c` are evaluated in `Priority__c` ascending order. As soon as one rule returns a result, the field is populated and no further rules for that field are evaluated.

### Match Score Fields

For every lookup field, a companion custom field is populated with the `Weight__c` of the winning rule. This provides a confidence audit trail without blocking any match.

| Lookup Field | Score Field |
|---|---|
| `DonorId` | `GEM_DonorMatchScore__c` |
| `GiftCommitmentId` | `GEM_GiftCommitmentMatchScore__c` |
| `OutreachSourceCodeId` | `GEM_OutreachSourceCodeMatchScore__c` |
| `CampaignId` | `GEM_CampaignMatchScore__c` |
| `GiftDesignation1Id` | `GEM_GiftDesignation1MatchScore__c` |
| `GiftDesignation2Id` | `GEM_GiftDesignation2MatchScore__c` |
| `GiftDesignation3Id` | `GEM_GiftDesignation3MatchScore__c` |

---

## Components

```
force-app/main/default/
├── classes/
│   ├── GiftEntryMatchingBatch.cls             # Main batch job
│   ├── GiftEntryMatchingBatchScheduler.cls    # Schedulable wrapper
│   ├── GiftEntryMatchingController.cls        # AuraEnabled controller for LWC
│   ├── GiftEntryMatchingRuleEvaluator.cls     # Token substitution & rule engine
│   └── GiftEntryMatchingBatchTest.cls         # Test coverage
├── customMetadata/
│   ├── GiftEntryMatchingRule.Donor_Match_By_Email.md-meta.xml
│   ├── GiftEntryMatchingRule.Donor_Match_By_Name.md-meta.xml
│   └── GiftEntryMatchingRule.GiftCommitment_Match_By_Donor.md-meta.xml
├── lwc/
│   └── giftEntryMatchingAction/               # Lightning component for GiftBatch page
│       ├── giftEntryMatchingAction.html
│       ├── giftEntryMatchingAction.js
│       └── giftEntryMatchingAction.js-meta.xml
└── objects/
    ├── GiftEntry/fields/                      # 7 GEM_*MatchScore__c fields
    └── GiftEntryMatchingRule__mdt/            # CMT object + fields
```

---

## GiftBatch Page Action

A Lightning Web Component (`giftEntryMatchingAction`) is included so users can trigger the matching batch directly from a **GiftBatch record page** — no anonymous Apex required.

### Adding to the GiftBatch Page

1. Open a **GiftBatch** record in Salesforce
2. Click the **gear icon → Edit Page** to open Lightning App Builder
3. In the left panel, search for **"Gift Entry Matching"**
4. Drag the component onto the page (sidebar or main column)
5. Click **Save → Activate**

### UI States

| State | What the user sees |
|---|---|
| **Idle** | "Run Gift Entry Matching" button |
| **Running** | Spinner with "Submitting batch job…" |
| **Success** | Green confirmation with the Apex Job ID |
| **Error** | Red error message with "Try Again" button |

On success, a toast notification also appears with the Job ID. Progress can be monitored under **Setup → Apex Jobs**.

---

## Deployment

### Deploy to Org

```bash
sf project deploy start --target-org <your-org-alias>
```

### Run the Batch (Anonymous Apex)

```apex
Id giftBatchId = '0CI000000000001AAA'; // Replace with your GiftBatch Id
Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), 50);
```

### Schedule Nightly

```apex
Id giftBatchId = '0CI000000000001AAA';
System.schedule(
    'Gift Entry Matching - Nightly',
    '0 0 2 * * ?',  // Every day at 2:00 AM
    new GiftEntryMatchingBatchScheduler(giftBatchId)
);
```

### Run Tests

```bash
sf apex run test --class-names GiftEntryMatchingBatchTest --target-org <your-org-alias> --result-format human
```

---

## Creating Matching Rules

1. In Salesforce Setup, go to **Custom Metadata Types → Gift Entry Matching Rule → Manage Records**
2. Click **New** and fill in:
   - **Label** — descriptive name (max 40 characters)
   - **Target Field** — e.g. `DonorId`
   - **Target Object** — e.g. `Account`
   - **SOQL WHERE Clause** — e.g. `PersonEmail = '{!GiftEntry.Email}' AND IsPersonAccount = true`
   - **Priority** — lower number runs first (e.g. `10`, `20`, `30`)
   - **Weight** — confidence score between `0.0` and `1.0`
   - **Is Active** — checked to enable

> **Tip:** Use gaps in priority numbers (10, 20, 30) so you can insert new rules later without renumbering.

### Using Custom Fields in Rules

Any `GiftEntry` field — including custom fields — can be used in a token. The batch automatically detects which fields your rules reference and adds them to the query. No code changes required.

```sql
-- Custom field example
MySegmentCode__c = '{!GiftEntry.MySegmentCode__c}'
```

---

## Available GiftEntry Fields for Tokens

All standard NPC `GiftEntry` fields are available out of the box:

`FirstName` · `LastName` · `Email` · `HomePhone` · `MobilePhone` · `Salutation` · `OrganizationName` · `Street` · `City` · `State` · `PostalCode` · `Country` · `GiftAmount` · `GiftType` · `GiftReceivedDate` · `PaymentMethod` · `PaymentIdentifier` · `Last4` · `ExpiryMonth` · `ExpiryYear` · `GiftProcessingStatus` · `GiftProcessingResult` · `IsNewRecurringGift` · `IsSetAsDefault` · `TransactionInterval` · `TransactionPeriod` · `TransactionDay` · `EffectiveStartDate` · `ExpectedEndDate` · `CheckDate` · `CurrencyIsoCode` · and more.

Any custom field referenced in a rule token is automatically added to the query.

---

## Behavior Notes

- **Does not overwrite**: If a lookup field already has a value, it is skipped entirely.
- **Sequential resolution**: Fields are resolved in the order listed above. A resolved value (e.g. `DonorId`) is immediately available as a token for subsequent fields in the same entry.
- **No match → leave blank**: If no rule produces a result, the field is left blank.
- **Ordered by date**: `GiftEntry` records in a batch are processed in `GiftReceivedDate ASC` order.
- **Partial success**: Batch DML uses `Database.update(records, false)` so a single failed record doesn't block others.

---

## Troubleshooting

Enable **Debug Logs** for your user in Setup with `Apex Code` level set to `INFO` or higher. Key log messages:

| Message | Meaning |
|---|---|
| `field [DonorId] has 0 active rule(s)` | No CMT records deployed for this field |
| `field [DonorId] already populated` | Field had a value — skipped |
| `token {!GiftEntry.FirstName} resolved to NULL` | Field name in token doesn't match GiftEntry API name |
| `GiftEntry populated field keys = {...}` | Lists all field names available for token substitution |
| `executing SOQL: SELECT Id FROM Account WHERE ...` | Full resolved query — verify field values look correct |
| `matched record Id=001... (score=0.8)` | Successful match |

---

## License

MIT
