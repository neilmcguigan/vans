A library of PostgreSQL PL/V8 functions for Validation, Analysis, Normalization, and Synthesis (VANS) of basic types.

Examples:

is_phone_number('800 GOT JUNK ext. 123', 'CA') -> true

normalize_phone_number('(604) 555-1212', 'CA') -> '+16045551212' //E164 format

analyze_phone_number('888.867.5309 x666') -> {country_code:1, national_number:8888675309, extension:'666', region_code:'US' }

is_hostname(text) returns boolean;
