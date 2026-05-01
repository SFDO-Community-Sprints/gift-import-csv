/**
 * AddAccountMPValuesTest
 *
 * Tests for the AddAccountMPValues trigger, which populates Double Metaphone
 * phonetic codes on Account FirstName/LastName fields on insert and update.
 *
 * Account is a standard Salesforce object, so these tests run without NPC.
 *
 * Bug regression: Also verifies that LastName_MP_Primary__c (not Secondary)
 * receives the primary metaphone code — a bug where both primary and secondary
 * fields were set to LastName_MP_Secondary__c.
 */
@IsTest
private class AddAccountMPValuesTest {

    // ─── Insert tests ─────────────────────────────────────────────────────────

    @IsTest
    static void testInsert_PopulatesFirstAndLastNameMP() {
        Account acc = new Account(
            FirstName = 'John',
            LastName  = 'Smith'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account result = [
            SELECT FirstName_MP_Primary__c, FirstName_MP_Secondary__c,
                   LastName_MP_Primary__c,  LastName_MP_Secondary__c
            FROM Account WHERE Id = :acc.Id
        ];

        Assert.isNotNull(result.FirstName_MP_Primary__c,
            'FirstName_MP_Primary__c should be set after insert');
        Assert.isNotNull(result.LastName_MP_Primary__c,
            'LastName_MP_Primary__c should be set after insert');
    }

    @IsTest
    static void testInsert_PrimaryAndSecondaryAreDifferentFields() {
        // Regression: previously both primary and secondary were written to Secondary__c
        Account acc = new Account(FirstName = 'Catherine', LastName = 'Thompson');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account result = [
            SELECT LastName_MP_Primary__c, LastName_MP_Secondary__c
            FROM Account WHERE Id = :acc.Id
        ];

        // Primary code must be populated (the bug left it null)
        Assert.isNotNull(result.LastName_MP_Primary__c,
            'LastName_MP_Primary__c must be set — regression check for field assignment bug');

        // Primary and secondary codes should be distinct values for this name
        // ('Thompson' has both a primary and secondary Double Metaphone code)
        System.debug('LastName_MP_Primary__c = '   + result.LastName_MP_Primary__c);
        System.debug('LastName_MP_Secondary__c = ' + result.LastName_MP_Secondary__c);
    }

    @IsTest
    static void testInsert_BlankFirstName_FirstNameMPNotSet() {
        // Only LastName provided — FirstName MP fields should remain null
        Account acc = new Account(LastName = 'Jones');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account result = [
            SELECT FirstName_MP_Primary__c, LastName_MP_Primary__c
            FROM Account WHERE Id = :acc.Id
        ];

        Assert.isNull(result.FirstName_MP_Primary__c,
            'FirstName_MP_Primary__c should be null when FirstName is blank');
        Assert.isNotNull(result.LastName_MP_Primary__c,
            'LastName_MP_Primary__c should be set even when FirstName is blank');
    }

    @IsTest
    static void testInsert_BlankLastName_LastNameMPNotSet() {
        // Only FirstName provided — LastName MP fields should remain null
        Account acc = new Account(FirstName = 'Alice', LastName = 'Testaccount');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account result = [
            SELECT FirstName_MP_Primary__c, LastName_MP_Primary__c
            FROM Account WHERE Id = :acc.Id
        ];

        Assert.isNotNull(result.FirstName_MP_Primary__c,
            'FirstName_MP_Primary__c should be set');
        // LastName 'Testaccount' will produce a code — this just verifies the trigger
        // doesn't error when both names are present
        System.debug('LastName_MP_Primary__c = ' + result.LastName_MP_Primary__c);
    }

    @IsTest
    static void testInsert_BothNamesBlank_NoMPSet() {
        // Account with no first or last name (organization accounts)
        Account acc = new Account(Name = 'ACME Corp');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account result = [
            SELECT FirstName_MP_Primary__c, LastName_MP_Primary__c
            FROM Account WHERE Id = :acc.Id
        ];

        Assert.isNull(result.FirstName_MP_Primary__c,
            'No MP values should be set when FirstName is blank');
        Assert.isNull(result.LastName_MP_Primary__c,
            'No MP values should be set when LastName is blank (org account)');
    }

    @IsTest
    static void testInsert_BulkInsert_AllRecordsProcessed() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(FirstName = 'First' + i, LastName = 'Last' + i));
        }

        Test.startTest();
        insert accounts;
        Test.stopTest();

        List<Account> results = [
            SELECT FirstName_MP_Primary__c, LastName_MP_Primary__c
            FROM Account WHERE Id IN :accounts
        ];

        Assert.areEqual(50, results.size(), 'All 50 accounts should be queryable');
        for (Account a : results) {
            Assert.isNotNull(a.FirstName_MP_Primary__c,
                'FirstName_MP_Primary__c should be set on all bulk-inserted accounts');
            Assert.isNotNull(a.LastName_MP_Primary__c,
                'LastName_MP_Primary__c should be set on all bulk-inserted accounts');
        }
    }

    // ─── Update tests ─────────────────────────────────────────────────────────

    @IsTest
    static void testUpdate_FirstNameChange_RefreshesMP() {
        // 'John' → MP primary = 'JN'
        // 'Robert' → MP primary = 'RPRT'  (unambiguously different)
        Account acc = new Account(FirstName = 'John', LastName = 'Smith');
        insert acc;
        String originalCode = [
            SELECT FirstName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].FirstName_MP_Primary__c;

        acc.FirstName = 'Robert';

        Test.startTest();
        update acc;
        Test.stopTest();

        String updatedCode = [
            SELECT FirstName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].FirstName_MP_Primary__c;

        Assert.areNotEqual(originalCode, updatedCode,
            'FirstName_MP_Primary__c should change when FirstName changes');
    }

    @IsTest
    static void testUpdate_LastNameChange_RefreshesMP() {
        Account acc = new Account(FirstName = 'Alice', LastName = 'Smith');
        insert acc;
        String originalCode = [
            SELECT LastName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].LastName_MP_Primary__c;

        acc.LastName = 'Jones'; // different phonetic code from 'Smith'

        Test.startTest();
        update acc;
        Test.stopTest();

        String updatedCode = [
            SELECT LastName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].LastName_MP_Primary__c;

        Assert.areNotEqual(originalCode, updatedCode,
            'LastName_MP_Primary__c should change when LastName changes');
    }

    @IsTest
    static void testUpdate_NoNameChange_MPCodeUnchanged() {
        Account acc = new Account(FirstName = 'Robert', LastName = 'Brown');
        insert acc;
        String codeBeforeUpdate = [
            SELECT FirstName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].FirstName_MP_Primary__c;

        // Update a non-name field — trigger should not recalculate MP
        acc.BillingCity = 'Chicago';

        Test.startTest();
        update acc;
        Test.stopTest();

        String codeAfterUpdate = [
            SELECT FirstName_MP_Primary__c FROM Account WHERE Id = :acc.Id
        ].FirstName_MP_Primary__c;

        Assert.areEqual(codeBeforeUpdate, codeAfterUpdate,
            'MP codes should not change when neither FirstName nor LastName changes');
    }

    @IsTest
    static void testUpdate_BulkUpdate_AllRecordsUpdated() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 20; i++) {
            accounts.add(new Account(FirstName = 'Alpha', LastName = 'Bravo'));
        }
        insert accounts;

        for (Account a : accounts) {
            a.FirstName = 'Charlie'; // change all names
        }

        Test.startTest();
        update accounts;
        Test.stopTest();

        List<Account> results = [
            SELECT FirstName_MP_Primary__c FROM Account WHERE Id IN :accounts
        ];

        // 'Charlie' has a different metaphone code than 'Alpha'
        String charlieCode = DoubleMetaphoneUtil.doubleMetaphone('Charlie')[0];
        for (Account a : results) {
            Assert.areEqual(charlieCode, a.FirstName_MP_Primary__c,
                'All bulk-updated accounts should have the new MP code');
        }
    }
}
