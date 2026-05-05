-- =========================================================
--  Generation de donnees factices :
--    - 20 utilisateurs (user01 .. user20)
--    - 100 lignes d'utilisation reparties sur 30 jours
--  Methode : cross-join sur une table de chiffres
--            + RAND() materialise dans une temp table
--            (sinon RAND() reevaluee a chaque iteration de JOIN)
-- =========================================================
USE nx_licenses_stats;

-- ---------- 20 utilisateurs ----------
INSERT INTO utilisateur (login)
SELECT CONCAT('user', LPAD(seq.n, 2, '0')) AS login
FROM (
    SELECT (a.d + b.d * 10) + 1 AS n
    FROM (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
         (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2) b
) AS seq
WHERE seq.n BETWEEN 1 AND 20
ORDER BY seq.n;

-- ---------- Cardinalites des referentiels ----------
SET @c_site := (SELECT COUNT(*) FROM site);
SET @c_user := (SELECT COUNT(*) FROM utilisateur);
SET @c_lic  := (SELECT COUNT(*) FROM licence);

-- ---------- Materialisation des tirages aleatoires ----------
DROP TEMPORARY TABLE IF EXISTS _gen;
CREATE TEMPORARY TABLE _gen (
    rid_site INT UNSIGNED NOT NULL,
    rid_user INT UNSIGNED NOT NULL,
    rid_lic  INT UNSIGNED NOT NULL,
    rpc_num  INT          NOT NULL,
    rdays    INT          NOT NULL,
    rsec     INT          NOT NULL,
    KEY ix_site (rid_site),
    KEY ix_user (rid_user),
    KEY ix_lic  (rid_lic)
) ENGINE=Memory;

INSERT INTO _gen (rid_site, rid_user, rid_lic, rpc_num, rdays, rsec)
SELECT
    1 + FLOOR(RAND() * @c_site)  AS rid_site,
    1 + FLOOR(RAND() * @c_user)  AS rid_user,
    1 + FLOOR(RAND() * @c_lic)   AS rid_lic,
    1 + FLOOR(RAND() * 9999)     AS rpc_num,
    FLOOR(RAND() * 30)           AS rdays,
    FLOOR(RAND() * 86400)        AS rsec
FROM (
    SELECT (a.d + b.d * 10 + c.d * 100) AS n
    FROM (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
         (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b,
         (SELECT 0 AS d UNION ALL SELECT 1) c
) AS nn
WHERE nn.n BETWEEN 1 AND 100;

-- ---------- Insertion finale ----------
INSERT INTO utilisation_licence (id_site, hostname, id_user, id_licence, date_utilisation)
SELECT
    s.id_site,
    CONCAT(s.code_site, '-PC-', LPAD(g.rpc_num, 4, '0')) AS hostname,
    u.id_user,
    l.id_licence,
    DATE_ADD(
        DATE_ADD(CURDATE(), INTERVAL -g.rdays DAY),
        INTERVAL g.rsec SECOND
    ) AS date_utilisation
FROM _gen g
JOIN site        s ON s.id_site    = g.rid_site
JOIN utilisateur u ON u.id_user    = g.rid_user
JOIN licence     l ON l.id_licence = g.rid_lic;

DROP TEMPORARY TABLE _gen;

-- ---------- Recap ----------
SELECT
    (SELECT COUNT(*) FROM pays)                AS nb_pays,
    (SELECT COUNT(*) FROM site)                AS nb_sites,
    (SELECT COUNT(*) FROM utilisateur)         AS nb_users,
    (SELECT COUNT(*) FROM licence)             AS nb_licences,
    (SELECT COUNT(*) FROM utilisation_licence) AS nb_utilisations;
