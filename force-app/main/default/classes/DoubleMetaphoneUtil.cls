public class DoubleMetaphoneUtil {

    private static final String VOWELS = 'AEIOUY';

    public static List<String> doubleMetaphone(String value) {
        if (String.isBlank(value)) return new List<String>{'', ''};

        String normalized = value.toUpperCase() + ' ';
        Integer length = normalized.length();
        Integer index = 0;

        String primary = '';
        String secondary = '';

        Boolean isSlavoGermanic = containsAny(normalized, new List<String>{'W', 'K', 'CZ', 'WITZ'});
        Boolean isGermanic = startsWithAny(normalized, new List<String>{'VAN ', 'VON ', 'SCH'});

        // Skip silent starters
        if (startsWithAny(normalized, new List<String>{'GN', 'KN', 'PN', 'WR', 'PS'})) index++;

        // Initial X
        if (charAt(normalized, 0) == 'X') {
            primary += 'S';
            secondary += 'S';
            index++;
        }

        while (index < length && primary.length() < 6) {
            String c = charAt(normalized, index);
            String prev = index > 0 ? charAt(normalized, index - 1) : '';
            String next = index + 1 < length ? charAt(normalized, index + 1) : '';
            String next2 = index + 2 < length ? charAt(normalized, index + 2) : '';

            switch on c {

                // ---- VOWELS ----
                when 'A', 'E', 'I', 'O', 'U' {
                    if (index == 0) {
                        primary += 'A';
                        secondary += 'A';
                    }
                    index++;
                }

                // ---- B ----
                when 'B' {
                    primary += 'P'; secondary += 'P';
                    index += (next == 'B') ? 2 : 1;
                }

                // ---- C (major upgrade) ----
                when 'C' {

                    // CH special cases
                    if (next == 'H') {
                        if (startsWithAt(normalized, index, 'CHAE') || isGermanic) {
                            primary += 'K'; secondary += 'K';
                        } else {
                            primary += 'X'; secondary += 'X';
                        }
                        index += 2;
                    }

                    // CIA
                    else if (startsWithAt(normalized, index, 'CIA')) {
                        primary += 'X'; secondary += 'X';
                        index += 3;
                    }

                    // CI CE CY
                    else if (next == 'I' || next == 'E' || next == 'Y') {
                        primary += 'S'; secondary += 'S';
                        index += 2;
                    }

                    // default
                    else {
                        primary += 'K'; secondary += 'K';
                        index += (next == 'C') ? 2 : 1;
                    }
                }

                // ---- D ----
                when 'D' {
                    if (next == 'G' && (next2 == 'E' || next2 == 'I' || next2 == 'Y')) {
                        primary += 'J'; secondary += 'J';
                        index += 3;
                    } else {
                        primary += 'T'; secondary += 'T';
                        index += (next == 'D') ? 2 : 1;
                    }
                }

                // ---- G (major upgrade) ----
                when 'G' {

                    if (next == 'H') {
                        Boolean prevIsVowel = prev != '' && VOWELS.contains(prev);
                        if (!prevIsVowel) {
                            primary += 'K'; secondary += 'K';
                        } else {
                            primary += 'F'; secondary += 'F';
                        }
                        index += 2;
                    }

                    else if (next == 'N') {
                        primary += 'N';
                        secondary += isSlavoGermanic ? 'K' : 'N';
                        index += 2;
                    }

                    else if (next == 'E' || next == 'I' || next == 'Y') {
                        primary += 'J';
                        secondary += isSlavoGermanic ? 'K' : 'J';
                        index += 2;
                    }

                    else {
                        primary += 'K'; secondary += 'K';
                        index += (next == 'G') ? 2 : 1;
                    }
                }

                // ---- H ----
                when 'H' {
                    Boolean prevIsVowel = prev != '' && VOWELS.contains(prev);
                    if (VOWELS.contains(next) && !prevIsVowel) {
                        primary += 'H'; secondary += 'H';
                    }
                    index++;
                }

                // ---- J ----
                when 'J' {
                    primary += 'J';
                    secondary += (isGermanic) ? 'J' : 'H';
                    index += (next == 'J') ? 2 : 1;
                }

                when 'K' {
                    primary += 'K'; secondary += 'K';
                    index += (next == 'K') ? 2 : 1;
                }

                when 'L' {
                    primary += 'L'; secondary += 'L';
                    index += (next == 'L') ? 2 : 1;
                }

                when 'M' {
                    primary += 'M'; secondary += 'M';
                    index += (next == 'M') ? 2 : 1;
                }

                when 'N' {
                    primary += 'N'; secondary += 'N';
                    index += (next == 'N') ? 2 : 1;
                }

                // ---- P ----
                when 'P' {
                    if (next == 'H') {
                        primary += 'F'; secondary += 'F';
                        index += 2;
                    } else {
                        primary += 'P'; secondary += 'P';
                        index += (next == 'P') ? 2 : 1;
                    }
                }

                when 'Q' {
                    primary += 'K'; secondary += 'K';
                    index += (next == 'Q') ? 2 : 1;
                }

                when 'R' {
                    primary += 'R'; secondary += 'R';
                    index += (next == 'R') ? 2 : 1;
                }

                // ---- S (major upgrade) ----
                when 'S' {
                    if (startsWithAt(normalized, index, 'SH')) {
                        primary += 'X'; secondary += 'X';
                        index += 2;
                    }
                    else if (startsWithAt(normalized, index, 'SCH')) {
                        primary += 'X'; secondary += 'SK';
                        index += 3;
                    }
                    else {
                        primary += 'S'; secondary += 'S';
                        index += (next == 'S') ? 2 : 1;
                    }
                }

                // ---- T ----
                when 'T' {
                    if (startsWithAt(normalized, index, 'TH')) {
                        primary += '0'; secondary += 'T';
                        index += 2;
                    }
                    else if (startsWithAt(normalized, index, 'TIO') || startsWithAt(normalized, index, 'TIA')) {
                        primary += 'X'; secondary += 'X';
                        index += 3;
                    }
                    else {
                        primary += 'T'; secondary += 'T';
                        index += (next == 'T') ? 2 : 1;
                    }
                }

                when 'V' {
                    primary += 'F'; secondary += 'F';
                    index += (next == 'V') ? 2 : 1;
                }

                // ---- W/Y ----
                when 'W', 'Y' {
                    if (VOWELS.contains(next)) {
                        primary += c;
                        secondary += c;
                    }
                    index++;
                }

                when 'X' {
                    primary += 'KS'; secondary += 'KS';
                    index++;
                }

                when 'Z' {
                    primary += 'S';
                    secondary += isSlavoGermanic ? 'TS' : 'S';
                    index += (next == 'Z') ? 2 : 1;
                }

                when else {
                    index++;
                }
            }
        }

        return new List<String>{primary, secondary};
    }

    private static String charAt(String s, Integer i) {
        return s.substring(i, i + 1);
    }

    private static Boolean startsWithAt(String s, Integer i, String pattern) {
        if (i + pattern.length() > s.length()) return false;
        return s.substring(i, i + pattern.length()) == pattern;
    }

    private static Boolean startsWithAny(String input, List<String> patterns) {
        for (String p : patterns) if (input.startsWith(p)) return true;
        return false;
    }

    private static Boolean containsAny(String input, List<String> patterns) {
        for (String p : patterns) if (input.contains(p)) return true;
        return false;
    }
}