@IsTest
private class DoubleMetaphoneUtilTest {

    @IsTest
    static void testNullAndBlankInputs() {
        // Test null input
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone(null);
        System.assertEquals('', result[0], 'Primary should be empty for null');
        System.assertEquals('', result[1], 'Secondary should be empty for null');

        // Test empty string
        result = DoubleMetaphoneUtil.doubleMetaphone('');
        System.assertEquals('', result[0], 'Primary should be empty for empty string');
        System.assertEquals('', result[1], 'Secondary should be empty for empty string');

        // Test whitespace only
        result = DoubleMetaphoneUtil.doubleMetaphone('   ');
        System.assertEquals('', result[0], 'Primary should be empty for whitespace');
        System.assertEquals('', result[1], 'Secondary should be empty for whitespace');
    }

    @IsTest
    static void testVowels() {
        // Initial vowels should be encoded as 'A'
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Anne');
        System.assertEquals('A', result[0].substring(0, 1), 'Should start with A');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Eric');
        System.assertEquals('A', result[0].substring(0, 1), 'Should start with A');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Ian');
        System.assertEquals('A', result[0].substring(0, 1), 'Should start with A');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Oscar');
        System.assertEquals('A', result[0].substring(0, 1), 'Should start with A');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Uma');
        System.assertEquals('A', result[0].substring(0, 1), 'Should start with A');
    }

    @IsTest
    static void testSilentStarters() {
        // These should skip the first letter
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Gnat');
        System.assertNotEquals('G', result[0].substring(0, 1), 'GN should skip G');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Knight');
        System.assertNotEquals('K', result[0].substring(0, 1), 'KN should skip K');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Pneumonia');
        System.assertNotEquals('P', result[0].substring(0, 1), 'PN should skip P');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Write');
        System.assertNotEquals('W', result[0].substring(0, 1), 'WR should skip W');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Psychology');
        System.assertNotEquals('P', result[0].substring(0, 1), 'PS should skip P');
    }

    @IsTest
    static void testInitialX() {
        // Initial X should be encoded as 'S'
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Xavier');
        System.assertEquals('S', result[0].substring(0, 1), 'Initial X should encode to S');
        System.assertEquals('S', result[1].substring(0, 1), 'Initial X should encode to S in secondary');
    }

    @IsTest
    static void testConsonantB() {
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Bob');
        System.assert(result[0].contains('P'), 'B should encode to P');
        
        // Double B
        result = DoubleMetaphoneUtil.doubleMetaphone('Rabbit');
        System.assert(result[0].contains('P'), 'BB should encode to P');
    }

    @IsTest
    static void testConsonantC() {
        // CH combinations
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Charles');
        System.assert(result[0].contains('X') || result[0].contains('K'), 'CH should encode appropriately');
        
        // CI, CE, CY
        result = DoubleMetaphoneUtil.doubleMetaphone('City');
        System.assert(result[0].contains('S'), 'CI should encode to S');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Central');
        System.assert(result[0].contains('S'), 'CE should encode to S');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Cycle');
        System.assert(result[0].contains('S'), 'CY should encode to S');
        
        // CIA
        result = DoubleMetaphoneUtil.doubleMetaphone('Ecia');
        System.assert(result[0].contains('X'), 'CIA should encode to X');
        
        // Default C
        result = DoubleMetaphoneUtil.doubleMetaphone('Cat');
        System.assert(result[0].contains('K'), 'C should encode to K by default');
    }

    @IsTest
    static void testConsonantD() {
        // DG before E, I, Y
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Edge');
        System.assert(result[0].contains('J'), 'DGE should encode to J');
        
        // Default D
        result = DoubleMetaphoneUtil.doubleMetaphone('David');
        System.assert(result[0].contains('T'), 'D should encode to T');
        
        // Double D
        result = DoubleMetaphoneUtil.doubleMetaphone('Ladder');
        System.assert(result[0].contains('T'), 'DD should encode to T');
    }

    @IsTest
    static void testConsonantG() {
        // GH combinations
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Laugh');
        System.assert(result[0].contains('K') || result[0].contains('F'), 'GH should encode appropriately');
        
        // GN
        result = DoubleMetaphoneUtil.doubleMetaphone('Sign');
        System.assert(result[0].contains('N'), 'GN should encode to N');
        
        // GE, GI, GY
        result = DoubleMetaphoneUtil.doubleMetaphone('George');
        System.assert(result[0].contains('J') || result[0].contains('K'), 'GE should encode to J or K');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Giant');
        System.assert(result[0].contains('J') || result[0].contains('K'), 'GI should encode to J or K');
        
        // Default G
        result = DoubleMetaphoneUtil.doubleMetaphone('Go');
        System.assert(result[0].contains('K'), 'G should encode to K by default');
    }

    @IsTest
    static void testConsonantH() {
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Hello');
        System.assertEquals('HL',result[0], 'H followed by vowel should encode to H');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Noah');
        System.assert(!result[0].contains('H'), 'H after vowel should be silent. Got: ' + result[0]);
    }

    @IsTest
    static void testConsonantJ() {
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('John');
        System.assert(result[0].contains('J'), 'J should encode to J');
        System.assert(result[1].contains('J') || result[1].contains('H'), 'J should encode to J or H in secondary');
    }

    @IsTest
    static void testConsonantP() {
        // PH
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Phone');
        System.assert(result[0].contains('F'), 'PH should encode to F');
        
        // Default P
        result = DoubleMetaphoneUtil.doubleMetaphone('Peter');
        System.assert(result[0].contains('P'), 'P should encode to P');
    }

    @IsTest
    static void testConsonantS() {
        // SH
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Sharon');
        System.assert(result[0].contains('X'), 'SH should encode to X');
        
        // SCH
        result = DoubleMetaphoneUtil.doubleMetaphone('School');
        System.assert(result[0].contains('X') || result[0].contains('SK'), 'SCH should encode appropriately');
        
        // Default S
        result = DoubleMetaphoneUtil.doubleMetaphone('Sam');
        System.assert(result[0].contains('S'), 'S should encode to S');
    }

    @IsTest
    static void testConsonantT() {
        // TH
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Thomas');
        System.assert(result[0].contains('0') || result[0].contains('T'), 'TH should encode to 0 or T');
        
        // TIO, TIA
        result = DoubleMetaphoneUtil.doubleMetaphone('Nation');
        System.assert(result[0].contains('X'), 'TIO should encode to X');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Partial');
        System.assert(result[0].contains('X'), 'TIA should encode to X');
        
        // Default T
        result = DoubleMetaphoneUtil.doubleMetaphone('Tom');
        System.assert(result[0].contains('T'), 'T should encode to T');
    }

    @IsTest
    static void testConsonantV() {
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Victor');
        System.assert(result[0].contains('F'), 'V should encode to F');
    }

    @IsTest
    static void testConsonantWY() {
        // W/Y followed by vowel
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Wayne');
        System.assert(result[0].contains('W') || result[0].length() > 0, 'W before vowel should encode');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Yale');
        System.assert(result[0].contains('Y') || result[0].length() > 0, 'Y before vowel should encode');
    }

    @IsTest
    static void testConsonantX() {
        // Non-initial X
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Alex');
        System.assert(result[0].contains('KS'), 'X should encode to KS');
    }

    @IsTest
    static void testConsonantZ() {
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Zoe');
        System.assert(result[0].contains('S'), 'Z should encode to S');
        
        // Double Z
        result = DoubleMetaphoneUtil.doubleMetaphone('Pizza');
        System.assert(result[0].contains('S'), 'ZZ should encode to S');
    }

    @IsTest
    static void testSlavoGermanicNames() {
        // Names with W, K, CZ, WITZ
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Kowalski');
        System.assertNotEquals(null, result[0], 'Should handle Slavo-Germanic name');
        System.assertNotEquals(null, result[1], 'Should have secondary encoding');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Horowitz');
        System.assertNotEquals(null, result[0], 'Should handle -witz name');
    }

    @IsTest
    static void testGermanicNames() {
        // VAN, VON, SCH
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Van Der Berg');
        System.assertNotEquals(null, result[0], 'Should handle Van name');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Von Schmidt');
        System.assertNotEquals(null, result[0], 'Should handle Von name');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Schultz');
        System.assertNotEquals(null, result[0], 'Should handle Sch name');
    }

    @IsTest
    static void testCommonNames() {
        // Test common first and last names
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Smith');
        System.assertEquals(2, result.size(), 'Should return primary and secondary');
        System.assertNotEquals('', result[0], 'Primary should not be empty');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Johnson');
        System.assertNotEquals('', result[0], 'Should encode Johnson');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Williams');
        System.assertNotEquals('', result[0], 'Should encode Williams');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Brown');
        System.assertNotEquals('', result[0], 'Should encode Brown');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Jones');
        System.assertNotEquals('', result[0], 'Should encode Jones');
    }

    @IsTest
    static void testPhoneticSimilarity() {
        // These should have similar encodings
        List<String> result1 = DoubleMetaphoneUtil.doubleMetaphone('Stephen');
        List<String> result2 = DoubleMetaphoneUtil.doubleMetaphone('Steven');
        System.assertEquals(result1[0], result2[0], 'Stephen and Steven should have same primary encoding');
        
        result1 = DoubleMetaphoneUtil.doubleMetaphone('Catherine');
        result2 = DoubleMetaphoneUtil.doubleMetaphone('Katherine');
        System.assertEquals(result1[0], result2[0], 'Catherine and Katherine should have same primary encoding');
    }

    @IsTest
    static void testMaxLengthEncoding() {
        // Test that encoding is limited to 6 characters
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Constantinopolitan');
        System.assert(result[0].length() <= 6, 'Primary encoding should be 6 characters or less');
        System.assert(result[1].length() <= 6, 'Secondary encoding should be 6 characters or less');
    }

    @IsTest
    static void testCaseInsensitivity() {
        List<String> result1 = DoubleMetaphoneUtil.doubleMetaphone('SMITH');
        List<String> result2 = DoubleMetaphoneUtil.doubleMetaphone('smith');
        List<String> result3 = DoubleMetaphoneUtil.doubleMetaphone('Smith');
        
        System.assertEquals(result1[0], result2[0], 'Should be case insensitive');
        System.assertEquals(result1[0], result3[0], 'Should be case insensitive');
        System.assertEquals(result1[1], result2[1], 'Secondary should be case insensitive');
        System.assertEquals(result1[1], result3[1], 'Secondary should be case insensitive');
    }

    @IsTest
    static void testDoubleConsonants() {
        // Test various double consonants
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('Bassett');
        System.assertNotEquals('', result[0], 'Should handle double S');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Garrett');
        System.assertNotEquals('', result[0], 'Should handle double R and double T');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Mccall');
        System.assertNotEquals('', result[0], 'Should handle double C');
    }

    @IsTest
    static void testSpecialCharactersAndSpaces() {
        // Test with spaces and special characters
        List<String> result = DoubleMetaphoneUtil.doubleMetaphone('O\'Brien');
        System.assertNotEquals('', result[0], 'Should handle apostrophe');
        
        result = DoubleMetaphoneUtil.doubleMetaphone('Mary-Jane');
        System.assertNotEquals('', result[0], 'Should handle hyphen');
    }

    @IsTest
    static void testBulkProcessing() {
        // Test processing multiple names
        List<String> names = new List<String>{
            'Anderson', 'Baker', 'Clark', 'Davis', 'Evans',
            'Fisher', 'Green', 'Harris', 'Jackson', 'King'
        };
        
        for (String name : names) {
            List<String> result = DoubleMetaphoneUtil.doubleMetaphone(name);
            System.assertNotEquals('', result[0], 'Should encode ' + name);
            System.assertEquals(2, result.size(), 'Should return 2 encodings for ' + name);
        }
    }
}