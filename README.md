VANs: A performant, test-driven PL/V8 library for Validation, Analysis, and Normalization of common types.

Examples:

    set search_path to vans;

    select assert_true( is_phone_number('800 GOT JUNK ext. 123', 'CA') );

    select assert_equals( '+18004685865', normalize_phone_number('1 (800) GOT-JUNK', 'CA') ); --E164 format

    select * from analyze_phone_number('888.867.5309 x666', 'US');

    country_code  national_number  extension  region_code   is_valid_number_for_region  number_type  area_code  local_number
    1             8888675309       666        US            true                        TOLL_FREE    888        8675309


    set vans.default_country_code = 'US';
    select assert_true( is_phone_number('800Starbuc') );

    select assert_false( is_hostname('a-.com') );

    select assert_equals( 'www.hotmail.com', normalize_hostname(' WWW.HOTMAIL.COM  ') );

Available settings:

set vans.default_country_code = 'US';  Used for telephone numbers and postal codes
set vans.allow_local_domains = false;  Used for email addresses and URLs.

More coming soon.

Todo:

- solid annotation parsing
- TAP or JUnit/surefire compatible output
- @Timed tests
- @Test(expected=exception_type)

