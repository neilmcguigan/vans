A library of PostgreSQL PL/V8 functions for Validation, Analysis, Normalization, and Synthesis (VANS) of basic types.

Examples:

    set search_path to vans;

    select assert_true( is_phone_number('800 GOT JUNK ext. 123', 'CA') );

    select assert_equals( '+18004685865', normalize_phone_number('1 (800) GOT-JUNK', 'CA') ); --E164 format

    select * from analyze_phone_number('888.867.5309 x666', 'CA');

    country_code    national_number     extension   region_code
    smallint        bigint              text        character(2)
    1               8888675309          '666'       'US'


    select assert_false( is_hostname('a-.com') );

    select assert_equals( 'www.hotmail.com', normalize_hostname(' WWW.HOTMAIL.COM  ') );

More coming soon.
