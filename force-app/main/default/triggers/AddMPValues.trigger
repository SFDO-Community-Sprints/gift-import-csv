trigger AddMPValues on GiftEntry (before insert, before update) {

    for (GiftEntry rec : Trigger.new) {

        if (!String.isBlank(rec.FirstName)) {
            List<String> firstCodes = DoubleMetaphoneUtil.doubleMetaphone(rec.FirstName);

            rec.FirstName_MP_Primary__c   = firstCodes[0];
            rec.FirstName_MP_Secondary__c = firstCodes[1];
        }

        if (!String.isBlank(rec.LastName)) {
            List<String> lastCodes = DoubleMetaphoneUtil.doubleMetaphone(rec.LastName);

            rec.LastName_MP_Primary__c   = lastCodes[0];
            rec.LastName_MP_Secondary__c = lastCodes[1];
        }
    }
}