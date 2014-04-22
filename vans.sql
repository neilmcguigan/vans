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
  THEN
  THEN RAISE EXCEPTION 'Assertion Error. Expected <%> but was <%>', expected, actual;
END if;
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

  BEGIN
    EXECUTE format('select vans.%s();', proc.proname);
--exception when raise_exception then raise notice 'exception';
  END;

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

SELECT
  run_all_tests();
