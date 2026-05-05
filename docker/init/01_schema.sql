-- =========================================================
--  BTS SIO - Stats Licences NX
--  Schema en 5 tables (3NF)
-- =========================================================
USE nx_licenses_stats;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS utilisation_licence;
DROP TABLE IF EXISTS site;
DROP TABLE IF EXISTS pays;
DROP TABLE IF EXISTS utilisateur;
DROP TABLE IF EXISTS licence;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------
--  pays : referentiel des pays
-- ---------------------------------------------------------
CREATE TABLE pays (
    id_pays   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nom_pays  VARCHAR(50)  NOT NULL,
    PRIMARY KEY (id_pays),
    UNIQUE KEY uk_pays_nom (nom_pays)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------
--  site : un site appartient a un pays
--         code_site = prefixe hostname (ex: 'FRGR' = Grandvillars)
-- ---------------------------------------------------------
CREATE TABLE site (
    id_site    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pays    INT UNSIGNED NOT NULL,
    code_site  CHAR(4)      NOT NULL,
    nom_site   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (id_site),
    UNIQUE KEY uk_site_code (code_site),
    KEY ix_site_pays (id_pays),
    CONSTRAINT fk_site_pays FOREIGN KEY (id_pays) REFERENCES pays (id_pays)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------
--  utilisateur : referentiel des logins
-- ---------------------------------------------------------
CREATE TABLE utilisateur (
    id_user  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    login    VARCHAR(20)  NOT NULL,
    PRIMARY KEY (id_user),
    UNIQUE KEY uk_user_login (login)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------
--  licence : catalogue des noms de licences
-- ---------------------------------------------------------
CREATE TABLE licence (
    id_licence    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nom_licence   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (id_licence),
    UNIQUE KEY uk_licence_nom (nom_licence)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------
--  utilisation_licence : table de faits
--    1 ligne = 1 prise de licence par un user, sur un PC, a un instant T
-- ---------------------------------------------------------
CREATE TABLE utilisation_licence (
    id_use            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_site           INT UNSIGNED    NOT NULL,
    hostname          VARCHAR(20)     NOT NULL,
    id_user           INT UNSIGNED    NOT NULL,
    id_licence        INT UNSIGNED    NOT NULL,
    date_utilisation  DATETIME        NOT NULL,
    PRIMARY KEY (id_use),
    KEY ix_use_site (id_site),
    KEY ix_use_user (id_user),
    KEY ix_use_lic  (id_licence),
    KEY ix_use_date (date_utilisation),
    KEY ix_use_host (hostname),
    CONSTRAINT fk_use_site    FOREIGN KEY (id_site)    REFERENCES site (id_site),
    CONSTRAINT fk_use_user    FOREIGN KEY (id_user)    REFERENCES utilisateur (id_user),
    CONSTRAINT fk_use_licence FOREIGN KEY (id_licence) REFERENCES licence (id_licence)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
