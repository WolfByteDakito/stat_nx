-- =========================================================
--  Seed des referentiels (pays, sites, licences)
-- =========================================================
USE nx_licenses_stats;

-- ---------- Pays ----------
INSERT INTO pays (nom_pays) VALUES
    ('France'),
    ('Allemagne'),
    ('Espagne'),
    ('Maroc'),
    ('Mexique'),
    ('Chine'),
    ('Etats-Unis'),
    ('Hongrie'),
    ('Republique Tcheque');

-- ---------- Sites ----------
INSERT INTO site (id_pays, code_site, nom_site)
SELECT p.id_pays, src.code_site, src.nom_site
FROM (
    SELECT 'France'             AS pays, 'FRDE' AS code_site, 'Delle'         AS nom_site UNION ALL
    SELECT 'France',             'FRDA', 'Dalse'                                          UNION ALL
    SELECT 'France',             'FRPU', 'Puiseux'                                        UNION ALL
    SELECT 'France',             'FRLF', 'LaFerte'                                        UNION ALL
    SELECT 'France',             'FRME', 'Melisey'                                        UNION ALL
    SELECT 'France',             'FRLU', 'Lure'                                           UNION ALL
    SELECT 'France',             'FRGR', 'Grandvillars'                                   UNION ALL
    SELECT 'France',             'FRDC', 'Datacenter'                                     UNION ALL
    SELECT 'Allemagne',          'DEME', 'Mellrichstadt'                                  UNION ALL
    SELECT 'Allemagne',          'DEKI', 'Kirspe'                                         UNION ALL
    SELECT 'Allemagne',          'DEHE', 'Heidelberg'                                     UNION ALL
    SELECT 'Espagne',            'ESFU', 'Fuenlabrada'                                    UNION ALL
    SELECT 'Maroc',              'MOTA', 'Tanger'                                         UNION ALL
    SELECT 'Mexique',            'MXMO', 'Monterrey'                                      UNION ALL
    SELECT 'Mexique',            'MXQU', 'Queretaro'                                      UNION ALL
    SELECT 'Chine',              'CNSH', 'Shanghai'                                       UNION ALL
    SELECT 'Chine',              'CNSU', 'Suzhou'                                         UNION ALL
    SELECT 'Etats-Unis',         'USLI', 'Livonia'                                        UNION ALL
    SELECT 'Etats-Unis',         'USLZ', 'Lake Zurich'                                    UNION ALL
    SELECT 'Hongrie',            'HUGR', 'Gyor'                                           UNION ALL
    SELECT 'Republique Tcheque', 'CZCE', 'Cejc'
) AS src
JOIN pays p ON p.nom_pays = src.pays;

-- ---------- Licences ----------
INSERT INTO licence (nom_licence) VALUES
    ('NX-CAD'),
    ('NX-CAM'),
    ('NX-SIM'),
    ('CATIA-V5'),
    ('SOLIDWORKS'),
    ('AUTOCAD'),
    ('MATLAB'),
    ('OFFICE'),
    ('VISIO'),
    ('TEAMCENTER');
