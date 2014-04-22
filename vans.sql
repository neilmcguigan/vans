CREATE EXTENSION IF NOT EXISTS plv8;

CREATE SCHEMA IF NOT EXISTS vans;

SET search_path TO vans;

CREATE OR REPLACE FUNCTION assert_true(ANYELEMENT)
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN
  IF NOT $1 IS TRUE
  THEN RAISE EXCEPTION 'Assertion Error. Expected <true> but was <%>', $1;
  END IF;
END $body$;

CREATE OR REPLACE FUNCTION assert_false(ANYELEMENT)
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN
  IF NOT $1 IS FALSE
  THEN RAISE EXCEPTION 'Assertion Error. Expected <false> but was <%>', $1;
  END IF;
END $body$;

CREATE OR REPLACE FUNCTION assert_null(ANYELEMENT)
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN
  IF NOT $1 IS null
  THEN RAISE EXCEPTION 'Assertion Error. Expected <null> but was <%>', $1;
  END IF;
END $body$;

CREATE OR REPLACE FUNCTION assert_equals(expected ANYELEMENT, actual ANYELEMENT)
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN
  IF NOT (($1 = $2) IS TRUE)
  THEN RAISE EXCEPTION 'Assertion Error. Expected <%> but was <%>', expected, actual;
  END IF;
END $body$;

CREATE OR REPLACE FUNCTION run_all_tests()
  RETURNS VOID LANGUAGE plpgsql AS $body$
DECLARE
  proc    pg_catalog.pg_proc%ROWTYPE;
  started TIMESTAMPTZ;
BEGIN

  FOR proc IN SELECT
                p.*
              FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n
                  ON pronamespace = n.oid
              WHERE nspname = 'vans' AND proname LIKE 'test_%'
              ORDER BY proname LOOP
    started = clock_timestamp();


    EXECUTE format('select vans.%s();', proc.proname);

    RAISE NOTICE '% vans.%()', to_char(clock_timestamp() - started, 'MI:SS:MS'), proc.proname;
  END LOOP;

END $body$;

CREATE OR REPLACE FUNCTION is_hostname(TEXT)
  RETURNS BOOLEAN STRICT IMMUTABLE LANGUAGE plv8 AS $$

  var MAX_LENGTH = 255;
  var HOSTNAME_REGEXP = /^(([a-z0-9]|[a-z0-9][a-z0-9\-]{0,61}[a-z0-9])\.)*([a-z0-9]|[a-z0-9][a-z0-9\-]{0,61}[a-z0-9])$/i;

  return ($1.length <= MAX_LENGTH) && HOSTNAME_REGEXP.test($1);

$$;

CREATE OR REPLACE FUNCTION test_is_hostname()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(is_hostname(null));

    PERFORM assert_false(is_hostname(' '));
    PERFORM assert_false(is_hostname('stuff_thing.com'));
    PERFORM assert_false(is_hostname(repeat('a', 64)));
    PERFORM assert_false(is_hostname(repeat('a', 63) || '.' || repeat('a', 63) || '.' || repeat('a', 63) || '.' ||
                                     repeat('a', 63) || '.' || repeat('a', 63)));
    PERFORM assert_false(is_hostname('a-.com'));
    PERFORM assert_false(is_hostname('-a.com'));

    PERFORM assert_true(is_hostname('com'));
    PERFORM assert_true(is_hostname('localhost'));
    PERFORM assert_true(is_hostname(repeat('a', 62)));
    PERFORM assert_true(is_hostname('hotmail.com'));
    PERFORM assert_true(is_hostname('HOTMAIL.COM'));
    PERFORM assert_true(is_hostname('hot-mail.com'));
    PERFORM assert_true(is_hostname('a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z'));

END $body$;

CREATE OR REPLACE FUNCTION is_phone_number(TEXT, CHAR(2))
  RETURNS BOOLEAN STRICT IMMUTABLE LANGUAGE plv8 AS $$

	  if(typeof i18n === 'undefined') {
		  plv8.find_function('vans.load_libphonenumber')();
	  }

	var phoneNumberUtil = i18n.phonenumbers.PhoneNumberUtil.getInstance();

	try{
		var phoneNumber = phoneNumberUtil.parse($1, $2);
		return phoneNumberUtil.isValidNumber(phoneNumber);
	} catch(exp) {
		if(exp === 'Invalid country calling code') {
			throw exp;
		}
		return false;
	}
$$;

CREATE OR REPLACE FUNCTION test_is_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(is_phone_number(null, null));

    PERFORM assert_true(is_phone_number('778-708-1945', 'CA'));
    PERFORM assert_true(is_phone_number('1.778.708.1945', 'CA'));
    PERFORM assert_true(is_phone_number('1 800 GOT JUNK', 'US'));

    perform assert_false(is_phone_number('6045551212','CH'));

END $body$;

CREATE OR REPLACE FUNCTION normalize_phone_number(TEXT, CHAR(2))
  RETURNS TEXT STRICT IMMUTABLE LANGUAGE plv8 AS $body$

	  if(typeof i18n === 'undefined') {
		  plv8.find_function('vans.load_libphonenumber')();
	  }

	  var phoneNumberUtil = i18n.phonenumbers.PhoneNumberUtil.getInstance();
		var phoneNumber = phoneNumberUtil.parse($1, $2);
		return phoneNumberUtil.format(phoneNumber, i18n.phonenumbers.PhoneNumberFormat.E164);

$body$;

CREATE OR REPLACE FUNCTION test_normalize_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(normalize_phone_number(null, null));

    PERFORM assert_equals('+17787081945', normalize_phone_number('778-708-1945', 'CA'));
    PERFORM assert_equals('+18004685865', normalize_phone_number('1 800 GOT JUNK', 'CA'));
    PERFORM assert_equals('+17787081945', normalize_phone_number('+17787081945 ext 123', 'CA'));

END $body$;

create or replace function analyze_phone_number(text, char(2)) returns phone_number strict immutable language plv8 as $body$

	  if(typeof i18n === 'undefined') {
		  plv8.find_function('vans.load_libphonenumber')();
	  }

	var phoneNumberUtil = i18n.phonenumbers.PhoneNumberUtil.getInstance();

		var phoneNumber = phoneNumberUtil.parse($1, $2);
		return { "country_code": phoneNumber.getCountryCode(), "national_number": phoneNumber.getNationalNumber(), "extension": phoneNumber.getExtension(), "region_code":phoneNumberUtil.getRegionCodeForNumber(phoneNumber)};

$body$;

CREATE OR REPLACE FUNCTION test_analyze_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(analyze_phone_number(null, null));

    perform assert_equals('(1,7787081945,,"CA")', analyze_phone_number('7787081945', 'CA'));
    perform assert_equals('(1,7787081945,"123","CA")', analyze_phone_number('7787081945 ext. 123', 'CA'));
    perform assert_equals('(1,8007827282,,"US")', analyze_phone_number('800-Starbuc', 'US'));
    perform assert_equals('(1,8888575309,666,"US")', analyze_phone_number('888.857.5309 x666', 'CA'));

    /* expected exceptions here: */
    perform assert_equals('(,,,)', analyze_phone_number('not a number', ''));
    exception when internal_error then return;

END $body$;

SELECT
  run_all_tests();
