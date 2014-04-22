A library of PostgreSQL PL/V8 functions for Validation, Analysis, Normalization, and Synthesis (VANS) of basic types.

Examples:

    set search_path to vans;

    select assert_true( is_phone_number('800 GOT JUNK ext. 123', 'CA') );

    select assert_equals( normalize_phone_number('(604) 555-1212', 'CA'), '+16045551212'); --E164 format

    select * from analyze_phone_number('888.867.5309 x666', 'CA');

    country_code    national_number     extension   region_code
    smallint        bigint              text        character(2)
    1               8888675309          '666'       'US'


    assert_false( is_hostname('a-.com') );

More coming soon.
