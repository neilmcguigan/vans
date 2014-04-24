/*
you should run load_libphonenumber.sql first.

available settings:
set vans.default_country_code = 'US';
set vans.allow_local_domains = false;

*/

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
comment on function run_all_tests() is ' Runs all functions in the vans schema that begin with test_ . The functions should have no parameters.  ';

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

create or replace function normalize_hostname(text) returns text strict immutable language plv8 as $body$
    return $1.trim().toLowerCase();
$body$;

create or replace function test_normalize_hostname() returns void language plpgsql as $body$
begin

    perform assert_null(normalize_hostname(null));

    perform assert_equals('localhost', normalize_hostname('localhost'));
    perform assert_equals('www.hotmail.com', normalize_hostname(' WWW.HoTMaIl.com  '));

end $body$;

create or replace function analyze_hostname(text) returns record strict immutable language plv8 as $body$
     throw 'Not implemented';
$body$;

set vans.default_country_code = 'CA';

drop type if exists phone_number cascade;

create type phone_number as (
  country_code smallint,
  national_number bigint,
  extension varchar(11),
  region_code char(2),
  is_valid_number_for_region boolean,
  number_type text,
  area_code smallint, --can be null (malta)
  local_number int
);

CREATE OR REPLACE FUNCTION is_phone_number(TEXT, CHAR(2))
  RETURNS BOOLEAN STRICT IMMUTABLE LANGUAGE plv8 AS $body$

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
$body$;

create or replace function is_phone_number(text) returns boolean strict volatile language sql as '
  select vans.is_phone_number($1, current_setting(''vans.default_country_code''));
';

CREATE OR REPLACE FUNCTION test_is_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(is_phone_number(null, null));

    PERFORM assert_true(is_phone_number('778-708-9999', 'CA'));
    PERFORM assert_true(is_phone_number('1.778.708.9999', 'CA'));
    PERFORM assert_true(is_phone_number('1 800 GOT JUNK', 'US'));

    perform assert_false(is_phone_number('6045551212','CH'));

    set local vans.default_country_code = 'CA';
    perform assert_true(is_phone_number('6045551212'));

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

create or replace function normalize_phone_number(text) returns TEXT strict volatile language sql as '
  select vans.normalize_phone_number($1, current_setting(''vans.default_country_code''));
';

CREATE OR REPLACE FUNCTION test_normalize_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(normalize_phone_number(null, null));

    PERFORM assert_equals('+17787089999', normalize_phone_number('778-708-9999', 'CA'));
    PERFORM assert_equals('+18004685865', normalize_phone_number('1 800 GOT JUNK', 'CA'));
    PERFORM assert_equals('+17787089999', normalize_phone_number('+17787089999 ext 123', 'CA'));

END $body$;

create or replace function analyze_phone_number(text, char(2)) returns phone_number strict immutable language plv8 as $body$

	  if(typeof i18n === 'undefined') {
		  plv8.find_function('vans.load_libphonenumber')();
	  }

	var phoneNumberUtil = i18n.phonenumbers.PhoneNumberUtil.getInstance();

		var phoneNumber = phoneNumberUtil.parse($1, $2);
		return { "country_code": phoneNumber.getCountryCode(), "national_number": phoneNumber.getNationalNumber(), "extension": phoneNumber.getExtension(), "region_code":phoneNumberUtil.getRegionCodeForNumber(phoneNumber)};

$body$;

create or replace function analyze_phone_number(text) returns phone_number strict volatile language sql as '
  select vans.analyze_phone_number($1, current_setting(''vans.default_country_code''));
';

CREATE OR REPLACE FUNCTION test_analyze_phone_number()
  RETURNS VOID LANGUAGE plpgsql AS $body$
BEGIN

    PERFORM assert_null(analyze_phone_number(null, null));

    perform assert_equals('(1,7787089999,,"CA",,,,)', analyze_phone_number('7787089999', 'CA'));
    perform assert_equals('(1,7787089999,"123","CA",,,,)', analyze_phone_number('7787089999 ext. 123', 'CA'));
    perform assert_equals('(1,8007827282,,"US",,,,)', analyze_phone_number('800-Starbuc', 'US'));
    perform assert_equals('(1,8888575309,666,"US",,,,)', analyze_phone_number('888.857.5309 x666', 'CA'));

    /* expected exceptions here: */
    perform assert_equals('(,,,,,,,)', analyze_phone_number('not a number', ''));
    exception when internal_error then return;

END $body$;

drop type if exists domain_name cascade;
create type domain_name as (
  public_suffix text,
  top_private_domain text
);

create or replace function is_domain_name(text) returns boolean strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function normalize_domain_name(text) returns text strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function analyze_domain_name(text) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function is_postal_code(postal_code text, country_code char(2)) returns boolean strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function is_postal_code(text) returns boolean strict volatile language sql as '
  select vans.is_postal_code($1, current_setting(''vans.default_country_code''));
';

create or replace function normalize_postal_code(postal_code text, country_code char(2)) returns text strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function normalize_postal_code(text) returns text strict volatile language sql as '
  select vans.normalize_postal_code($1, current_setting(''vans.default_country_code''));
';

create or replace function analyze_postal_code(postal_code text, country_code char(2)) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function analyze_postal_code(text) returns record strict volatile language sql as '
  select vans.analyze_postal_code($1, current_setting(''vans.default_country_code''));
';

drop type if exists email_address cascade;
create type email_address as (
  local_part text,
  domain_part text,
  tag text,
  comments text[],
  is_webmail boolean
);

create or replace function is_email_address(text) returns boolean strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function normalize_email_address(text) returns text strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function analyze_email_address(text) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

drop type if exists url cascade;
create type url as (
  protocol text,
  host text,
  host_no_www text,
  port smallint,
  defaultPort smallint,
  file text,
  path text,
  query text,
  anchor text
);

create or replace function is_url(text) returns boolean strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function normalize_url(text) returns text strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

create or replace function analyze_url(text) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;

drop type if exists ip_geo cascade;
create type ip_geo as (
  continent_code char(2),
  country_code char(2),
  region_code char(5),
  city_name text,
  postal_code text,
  longitude decimal(9,6),
  latitude decimal(8,6),
  area_code smallint,
  metro_code smallint
);

create or replace function analyze_ip_address(inet) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;
comment on function analyze_ip_address(inet) is 'Returns geo information and reverse dns name.';

SELECT
  run_all_tests();
