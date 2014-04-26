/*
you should run load_libphonenumber.sql first.

available settings:
set vans.default_country_code = 'US';
set vans.allow_local_domains = false;

*/

CREATE EXTENSION IF NOT EXISTS plv8;

CREATE SCHEMA IF NOT EXISTS vans;

set vans.default_country_code = 'CA';
set vans.allow_local_domains = false;

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
              WHERE nspname = 'vans' AND proname LIKE 'test_%' and coalesce(obj_description(p.oid), '') !~* '@ignore'
              ORDER BY proname LOOP
    started = clock_timestamp();

    execute format('select vans.%I();', proc.proname);

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
comment on function test_is_hostname() is '';

create or replace function normalize_hostname(text) returns text strict immutable language plv8 as $body$
    return $1.trim().toLowerCase();
$body$;

create or replace function test_normalize_hostname() returns void language plpgsql as $body$
begin

    perform assert_null(normalize_hostname(null));

    perform assert_equals('localhost', normalize_hostname('localhost'));
    perform assert_equals('www.hotmail.com', normalize_hostname(' WWW.HoTMaIl.com  '));

end $body$;

drop type if exists hostname cascade;
create type hostname as (
  labels text[]
);

create or replace function analyze_hostname(text) returns hostname strict immutable language plv8 as $body$
     return { "labels": $1.split(/\./) };
$body$;

create or replace function test_analyze_hostname() returns void language plpgsql as $body$
begin
  perform assert_equals( '("{www,wikipedia,org}")', analyze_hostname('www.wikipedia.org') );
end $body$;

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

    PERFORM assert_true(is_phone_number('778-708-9999', 'ca'));
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

    PERFORM assert_equals('+17787089999', normalize_phone_number('778-708-9999', 'cA'));
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

create or replace function analyze_phone_number(text) returns phone_number strict volatile language sql as '
  select vans.analyze_phone_number($1, current_setting(''vans.default_country_code''));
';

drop type if exists domain_name cascade;
create type domain_name as (
  public_suffix text,
  top_private_domain text
);

create or replace function is_domain_name(text) returns boolean strict immutable language plv8 as $body$

    const REGEXP = /^(([a-z0-9]|[a-z0-9][a-z0-9\-]{0,61}[a-z0-9])\.)+([a-z]{2,})$/i;
    const MAX_LEN = 253;
    const TLDS = ['ac','ad','ae','aero','af','ag','ai','al','am','an','ao','aq','ar','arpa','as','asia','at','au','aw','ax','az','ba','bb','bd','be','bf','bg','bh','bi','biz','bj','bm','bn','bo','br','bs','bt','bv','bw','by','bz','ca','cat','cc','cd','cf','cg','ch','ci','ck','cl','cm','cn','co','com','coop','cr','cu','cv','cw','cx','cy','cz','de','dj','dk','dm','do','dz','ec','edu','ee','eg','er','es','et','eu','fi','fj','fk','fm','fo','fr','ga','gb','gd','ge','gf','gg','gh','gi','gl','gm','gn','gov','gp','gq','gr','gs','gt','gu','gw','gy','hk','hm','hn','hr','ht','hu','id','ie','il','im','in','info','int','io','iq','ir','is','it','je','jm','jo','jobs','jp','ke','kg','kh','ki','km','kn','kp','kr','kw','ky','kz','la','lb','lc','li','lk','lr','ls','lt','lu','lv','ly','ma','mc','md','me','mg','mh','mil','mk','ml','mm','mn','mo','mobi','mp','mq','mr','ms','mt','mu','museum','mv','mw','mx','my','mz','na','name','nc','ne','net','nf','ng','ni','nl','no','np','nr','nu','nz','om','org','pa','pe','pf','pg','ph','pk','pl','pm','pn','post','pr','pro','ps','pt','pw','py','qa','re','ro','rs','ru','rw','sa','sb','sc','sd','se','sg','sh','si','sj','sk','sl','sm','sn','so','sr','ss','st','su','sv','sx','sy','sz','tc','td','tel','tf','tg','th','tj','tk','tl','tm','tn','to','tp','tr','travel','tt','tv','tw','tz','ua','ug','uk','us','uy','uz','va','vc','ve','vg','vi','vn','vu','wf','ws','xxx','ye','yt','za','zm','zw'];

    var matches = $1.match(REGEXP);
    if(matches === null || $1.length > MAX_LEN) return false;

    return TLDS.indexOf(matches[matches.length-1].toLowerCase()) != -1;

$body$;

create or replace function test_is_domain_name() returns void language plpgsql as $body$
begin

    perform assert_null( is_domain_name(null) );

    perform assert_false(is_domain_name(' '));
    perform assert_false(is_domain_name('a'));
    perform assert_false(is_domain_name('a-.com'));										--hostname cannot begin or end with "-", though can contain between alphanums
    perform assert_false(is_domain_name('-aa.com'));
    perform assert_false(is_domain_name('www.hot_mail.com'));							--underscores not allowed
    perform assert_false(is_domain_name('www.hotmail.moc'));							--moc is not a top-level domain
    perform assert_false(is_domain_name('com'));										--is a tld, but not a domain name
    perform assert_false(is_domain_name('localhost'));
    perform assert_false(is_domain_name(repeat('a', 64) || '.com')); 					--label too long (63 max)
    perform assert_false(is_domain_name(repeat(repeat('a', 62) || '.', 4) || 'ca'));	--overall length too long (253 max)

    perform assert_true(is_domain_name(repeat('a', 63) || '.com'));						--long label ok
    perform assert_true(is_domain_name(repeat(repeat('a', 63) || '.', 3) || 'com'));	--long label ok
    perform assert_true(is_domain_name(repeat('a.', 125) || 'com'));					--lots of labels ok
    perform assert_true(is_domain_name('www.hot-mail.com'));
    perform assert_true(is_domain_name('WWW.HOTMAIL.COM'));
    perform assert_true(is_domain_name('x.mil'));
    perform assert_true(is_domain_name('a-b.com'));
    perform assert_true(is_domain_name('a9.com'));
    perform assert_true(is_domain_name('9a.com'));
    perform assert_true(is_domain_name('a.bc.def.museum'));

end $body$;

create or replace function normalize_domain_name(text) returns text strict immutable language plv8 as $body$
    return $1.trim().toLowerCase();
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
  hostname text,
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

drop type if exists ip_info cascade;
create type ip_info as (
  continent_code char(2),
  country_code char(2),
  region_code char(5),
  city_name text,
  postal_code text,
  longitude decimal(9,6),
  latitude decimal(8,6),
  area_code smallint,
  metro_code smallint,
  domain_name text
);

create or replace function analyze_ip_address(inet) returns record strict immutable language plv8 as $body$
    throw 'Not implemented';
$body$;
comment on function analyze_ip_address(inet) is 'Returns geo information and reverse dns name.';

SELECT
  run_all_tests();

