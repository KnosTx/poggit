DROP TABLE IF EXISTS users;
CREATE TABLE users (
    uid       INT UNSIGNED PRIMARY KEY,
    name      VARCHAR(255) UNIQUE,
    token     VARCHAR(64),
    scopes    VARCHAR(511)   DEFAULT '',
    email     VARCHAR(511)   DEFAULT '',
    lastLogin TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    lastNotif TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    opts      VARCHAR(15000) DEFAULT '{}'
);
DROP TABLE IF EXISTS user_ips;
CREATE TABLE user_ips (
    uid  INT UNSIGNED,
    ip   VARCHAR(100),
    time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (uid, ip),
    FOREIGN KEY (uid) REFERENCES users (uid)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS repos;
CREATE TABLE repos (
    repoId     INT UNSIGNED PRIMARY KEY,
    owner      VARCHAR(256),
    name       VARCHAR(256),
    private    BIT(1),
    build      BIT(1) DEFAULT 0,
    fork       TINYINT(1),
    accessWith INT UNSIGNED REFERENCES users (uid),
    webhookId  BIGINT UNSIGNED,
    webhookKey BINARY(8),
    KEY full_name (owner, name)
);
DROP TABLE IF EXISTS submit_rules;
CREATE TABLE submit_rules (
    id varchar(10) NOT NULL,
    title varchar(1000) DEFAULT NULL,
    content text,
    uses int(11) DEFAULT '0',
    PRIMARY KEY (id)
);
DROP TABLE IF EXISTS projects;
CREATE TABLE projects (
    projectId INT UNSIGNED PRIMARY KEY,
    repoId    INT UNSIGNED,
    name      VARCHAR(255),
    path      VARCHAR(1000),
    type      TINYINT UNSIGNED, -- Plugin = 0, Library = 1
    framework VARCHAR(100), -- default, nowhere
    lang      BIT(1),
    UNIQUE KEY repo_proj (repoId, name),
    FOREIGN KEY (repoId) REFERENCES repos (repoId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS project_subs;
CREATE TABLE project_subs (
    projectId INT UNSIGNED REFERENCES projects (projectId),
    userId    INT UNSIGNED REFERENCES users (uid),
    level     TINYINT DEFAULT 1, -- New Build = 1
    UNIQUE KEY user_project (userId, projectId)
);
DROP TABLE IF EXISTS resources;
CREATE TABLE resources (
    resourceId    BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    type          VARCHAR(100), -- phar, md, png, zip, etc.
    mimeType      VARCHAR(100),
    created       TIMESTAMP(3)                DEFAULT CURRENT_TIMESTAMP(3),
    accessFilters JSON                        NOT NULL,
    dlCount       BIGINT                      DEFAULT 0,
    duration      INT UNSIGNED,
    relMd         BIGINT UNSIGNED             DEFAULT NULL REFERENCES resources (resourceId),
    src           VARCHAR(40),
    fileSize      INT                         DEFAULT -1
)
    AUTO_INCREMENT = 2;
INSERT INTO resources (resourceId, type, mimeType, accessFilters, dlCount, duration, fileSize)
VALUES (1, '', 'text/plain', '[]', 0, 315360000, 0);
DROP TABLE IF EXISTS builds;
CREATE TABLE builds (
    buildId         BIGINT UNSIGNED PRIMARY KEY,
    resourceId      BIGINT UNSIGNED REFERENCES resources (resourceId),
    projectId       INT UNSIGNED,
    class           TINYINT, -- Dev = 1, PR = 4
    branch          VARCHAR(255)    DEFAULT 'master',
    sha             CHAR(40),
    cause           VARCHAR(8191),
    internal        INT, -- internal (project,class) build number, as opposed to global build number
    created         TIMESTAMP(3)    DEFAULT CURRENT_TIMESTAMP(3),
    triggerUser     INT UNSIGNED    DEFAULT 0, -- not necessarily REFERENCES users(uid), because may not have registered on Poggit yet
    logRsr          BIGINT UNSIGNED DEFAULT 1,
    path            VARCHAR(1000),
    main            VARCHAR(255) DEFAULT NULL,
    buildsAfterThis SMALLINT        DEFAULT 0, -- a temporary column for checking build completion
    KEY builds_by_project (projectId),
    FOREIGN KEY (projectId) REFERENCES projects (projectId)
        ON DELETE CASCADE,
    FOREIGN KEY (logRsr) REFERENCES resources (resourceId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS builds_statuses;
CREATE TABLE builds_statuses (
    buildId BIGINT UNSIGNED,
    level   TINYINT           NOT NULL,
    class   VARCHAR(255)      NOT NULL,
    body    TEXT DEFAULT '{}' NOT NULL,
    KEY statuses_by_build(buildId),
    KEY statuses_by_level(buildId, level),
    FOREIGN KEY (buildId) REFERENCES builds (buildId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS virion_builds;
CREATE TABLE virion_builds (
    buildId BIGINT UNSIGNED,
    version VARCHAR(255) NOT NULL,
    api     VARCHAR(255) NOT NULL, -- JSON-encoded
    FOREIGN KEY (buildId) REFERENCES builds (buildId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS virion_usages;
CREATE TABLE virion_usages (
    virionBuild BIGINT UNSIGNED,
    userBuild   BIGINT UNSIGNED,
    FOREIGN KEY (virionBuild) REFERENCES builds (buildId)
        ON DELETE CASCADE,
    FOREIGN KEY (userBuild) REFERENCES builds (buildId)
        ON DELETE CASCADE
);
CREATE OR REPLACE VIEW recent_virion_usages AS
SELECT virion_build.projectId virionProject, user_build.projectId userProject,
        UNIX_TIMESTAMP() - MAX(UNIX_TIMESTAMP(user_build.created)) sinceLastUse
FROM virion_usages
         INNER JOIN builds virion_build ON virion_usages.virionBuild = virion_build.buildId
         INNER JOIN builds user_build ON virion_usages.userBuild = user_build.buildId
GROUP BY virion_build.projectId, user_build.projectId
ORDER BY sinceLastUse;
DROP TABLE IF EXISTS namespaces;
CREATE TABLE namespaces (
    nsid   INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name   VARCHAR(255)     NOT NULL UNIQUE,
    parent INT UNSIGNED             DEFAULT NULL REFERENCES namespaces (id),
    depth  TINYINT UNSIGNED NOT NULL,
    KEY ns_by_depth(depth)
)
    AUTO_INCREMENT = 2;
DROP TABLE IF EXISTS known_classes;
CREATE TABLE known_classes (
    clid   INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    parent INT UNSIGNED             DEFAULT NULL REFERENCES namespaces (id),
    name   VARCHAR(255),
    KEY cl_by_parent(parent),
    UNIQUE KEY cl_by_fqn(parent, name)
)
    AUTO_INCREMENT = 2;
DROP TABLE IF EXISTS class_occurrences;
CREATE TABLE class_occurrences (
    clid    INT UNSIGNED REFERENCES known_classes (clid),
    buildId BIGINT UNSIGNED,
    FOREIGN KEY (buildId) REFERENCES builds (buildId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS known_commands;
CREATE TABLE known_commands (
    name        VARCHAR(255),
    description VARCHAR(255),
    `usage`       VARCHAR(255),
    class       VARCHAR(255),
    buildId     BIGINT UNSIGNED,
    PRIMARY KEY (name, buildId),
    KEY name (name),
    FULLTEXT (description),
    FULLTEXT (`usage`),
    FOREIGN KEY (buildId) REFERENCES builds (buildId)
        ON DELETE CASCADE
);
DROP TABLE IF ExISTS known_aliases;
CREATE TABLE known_aliases (
    name    VARCHAR(255),
    buildId BIGINT UNSIGNED,
    alias   VARCHAR(255),
    PRIMARY KEY (name, buildId, alias),
    KEY alias (alias),
    FOREIGN KEY (name, buildId) REFERENCES known_commands (name, buildId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS known_spoons;
CREATE TABLE known_spoons (
    id   SMALLINT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(16) UNIQUE,
    php varchar(5) DEFAULT '7.2',
    incompatible tinyint(1) NOT NULL,
    indev tinyint(1) NOT NULL,
    supported tinyint(1) NOT NULL DEFAULT '0',
    pharDefault varchar(255) DEFAULT NULL
);
DROP TABLE IF EXISTS releases;
CREATE TABLE releases (
    releaseId        INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    parent_releaseId INT UNSIGNED,
    name             VARCHAR(255),
    shortDesc        VARCHAR(255)             DEFAULT '',
    artifact         BIGINT UNSIGNED REFERENCES resources (resourceId),
    projectId        INT UNSIGNED,
    buildId          BIGINT UNSIGNED REFERENCES builds (buildId),
    version          VARCHAR(100), -- user-defined version ID, may duplicate
    description      BIGINT UNSIGNED REFERENCES resources (resourceId),
    icon             VARCHAR(511)             DEFAULT NULL, -- url to GitHub raw
    changelog        BIGINT UNSIGNED REFERENCES resources (resourceId),
    license          VARCHAR(100), -- name of license, or 'file'
    licenseRes       BIGINT                   DEFAULT 1, -- resourceId of license, only set if `license` is set to 'file'
    flags            SMALLINT                 DEFAULT 0, -- for example, featured
    creation         TIMESTAMP                DEFAULT CURRENT_TIMESTAMP,
    state            TINYINT                  DEFAULT 0,
    updateTime       TIMESTAMP                DEFAULT CURRENT_TIMESTAMP,
    assignee         INT UNSIGNED,
    adminNote        TEXT,
    KEY releases_by_project (projectId),
    KEY releases_by_name (name),
    FOREIGN KEY (projectId) REFERENCES projects (projectId)
        ON DELETE CASCADE,
    FOREIGN KEY (assignee) REFERENCES users (uid)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_authors;
CREATE TABLE release_authors (
    projectId INT UNSIGNED,
    uid       INT UNSIGNED, -- may not be registered on Poggit
    name      VARCHAR(32),
    level     TINYINT, -- collaborator = 1, contributor = 2, translator = 3, requester = 4
    UNIQUE KEY (projectId, uid),
    FOREIGN KEY (projectId) REFERENCES projects (projectId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_categories;
CREATE TABLE release_categories (
    projectId      INT UNSIGNED,
    category       SMALLINT UNSIGNED NOT NULL,
    isMainCategory BIT(1)            NOT NULL DEFAULT 0,
    UNIQUE KEY (projectId, category),
    FOREIGN KEY (projectId) REFERENCES projects (projectId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_keywords;
CREATE TABLE release_keywords (
    projectId INT UNSIGNED,
    word      VARCHAR(100) NOT NULL,
    FOREIGN KEY (projectId) REFERENCES projects (projectId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS spoon_prom;
CREATE TABLE spoon_prom (
    name varchar(50) NOT NULL,
    value varchar(16) DEFAULT NULL,
    PRIMARY KEY (name),
    KEY value (value),
    CONSTRAINT spoon_prom_ibfk_1 FOREIGN KEY (value) REFERENCES known_spoons (name)
);
DROP TABLE IF EXISTS spoon_desc;
CREATE TABLE spoon_desc (
    api varchar(20) DEFAULT NULL,
    value varchar(500) DEFAULT NULL,
    KEY api (api)
);
DROP TABLE IF EXISTS release_spoons;
CREATE TABLE release_spoons (
    releaseId INT UNSIGNED,
    since     VARCHAR(16),
    till      VARCHAR(16),
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE,
    FOREIGN KEY (since) REFERENCES known_spoons (name),
    FOREIGN KEY (till) REFERENCES known_spoons (name)
);
DROP TABLE IF EXISTS release_deps;
CREATE TABLE release_deps (
    releaseId INT UNSIGNED,
    name      VARCHAR(100) NOT NULL,
    version   VARCHAR(100) NOT NULL,
    depRelId  INT UNSIGNED DEFAULT NULL,
    isHard    BIT(1),
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_reqr;
CREATE TABLE release_reqr (
    releaseId INT UNSIGNED,
    type      TINYINT,
    details   VARCHAR(255) DEFAULT '',
    isRequire BIT(1),
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_perms;
CREATE TABLE release_perms (
    releaseId INT UNSIGNED DEFAULT NULL,
    val       TINYINT      DEFAULT NULL,
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_reviews;
CREATE TABLE release_reviews (
    reviewId  INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    releaseId INT UNSIGNED,
    user      INT UNSIGNED REFERENCES users (uid),
    criteria  INT UNSIGNED,
    type      TINYINT UNSIGNED, -- Official = 1, User = 2, Robot = 3
    cat       TINYINT UNSIGNED, -- perspective: code? test?
    score     SMALLINT UNSIGNED,
    message   VARCHAR(8191)            DEFAULT '',
    created   TIMESTAMP NOT NULL       DEFAULT CURRENT_TIMESTAMP,
    KEY reviews_by_plugin (releaseId),
    KEY reviews_by_plugin_user (releaseId, user),
    UNIQUE KEY reviews_by_plugin_user_criteria (releaseId, user, criteria),
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_reply_reviews;
CREATE TABLE release_reply_reviews (
    reviewId INT UNSIGNED,
    user     INT UNSIGNED,
    message  VARCHAR(8191),
    created  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (reviewId, user),
    FOREIGN KEY (reviewId) REFERENCES release_reviews (reviewId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_votes;
CREATE TABLE release_votes (
    user      INT UNSIGNED REFERENCES users (uid),
    releaseId INT UNSIGNED REFERENCES releases (releaseId),
    vote      TINYINT,
    message   VARCHAR(255)       DEFAULT '',
    updated   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY user_releaseId (user, releaseId),
    FOREIGN KEY (releaseId) REFERENCES releases (releaseId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS release_watches;
CREATE TABLE release_watches (
    uid       INT UNSIGNED REFERENCES users (uid),
    projectId INT UNSIGNED REFERENCES projects (projectId)
);
DROP TABLE IF EXISTS category_watches;
CREATE TABLE category_watches (
    uid      INT UNSIGNED REFERENCES users (uid),
    category SMALLINT UNSIGNED NOT NULL
);
DROP TABLE IF EXISTS event_timeline;
CREATE TABLE event_timeline (
    eventId BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    created TIMESTAMP                   DEFAULT CURRENT_TIMESTAMP,
    type    SMALLINT UNSIGNED NOT NULL,
    details VARCHAR(8191)
)
    AUTO_INCREMENT = 1;
INSERT INTO event_timeline (type, details)
VALUES (1, '{}');
DROP TABLE IF EXISTS user_timeline;
CREATE TABLE user_timeline (
    eventId BIGINT UNSIGNED REFERENCES event_timeline (eventId),
    userId  INT UNSIGNED REFERENCES users (uid),
    PRIMARY KEY (eventId, userId)
);
DROP TABLE IF EXISTS users_online;
CREATE TABLE users_online (
    ip     VARCHAR(40) PRIMARY KEY,
    lastOn TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
DROP TABLE IF EXISTS rsr_dl_ips;
CREATE TABLE rsr_dl_ips (
    resourceId BIGINT UNSIGNED,
    ip         VARCHAR(100),
    latest     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    count      INT       DEFAULT 1,
    PRIMARY KEY (resourceId, ip),
    FOREIGN KEY (resourceId) REFERENCES resources (resourceId)
        ON DELETE CASCADE
);
DROP TABLE IF EXISTS ext_refs;
CREATE TABLE ext_refs (
    srcDomain VARCHAR(255) PRIMARY KEY,
    cnt       BIGINT DEFAULT 1
);


INSERT INTO known_spoons (id, name, php, incompatible, indev, supported, pharDefault)
VALUES  (32, '3.0.0', '7.2', true, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.0.0/PocketMine-MP.phar'),
(40, '3.1.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.1.0/PocketMine-MP.phar'),
(46, '3.2.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.2.0/PocketMine-MP.phar'),
(53, '3.3.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.3.0/PocketMine-MP.phar'),
(58, '3.4.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.4.0/PocketMine-MP.phar'),
(60, '3.5.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.5.0/PocketMine-MP.phar'),
(71, '3.6.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.6.0/PocketMine-MP.phar'),
(77, '3.7.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.7.0/PocketMine-MP.phar'),
(81, '3.8.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.8.0/PocketMine-MP.phar'),
(89, '3.9.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.9.0/PocketMine-MP.phar'),
(94, '3.10.0', '7.2', false, false, false, 'https://github.com/pmmp/PocketMine-MP/releases/download/3.10.0/PocketMine-MP.phar');

INSERT INTO spoon_desc (api, value)
VALUES  ("3.0.0", "MCPE 1.4 Support"),
("3.1.0", "MCPE 1.5 Support"),
("3.2.0", "MCPE 1.6 Support"),
("3.3.0", "MCPE 1.7 Support"),
("3.4.0", ""),
("3.5.0", "MCPE 1.8 Support"),
("3.6.0", "MCPE 1.9 Support"),
("3.7.0", "MCPE 1.10 Support"),
("3.8.0", "MCPE 1.11 Support"),
("3.9.0", "MCPE 1.12 Support"),
("3.10.0", "MCPE 1.13 Support");

INSERT INTO spoon_prom (name, value)
VALUES  ("poggit.pmapis.promoted", "3.10.0"),
("poggit.pmapis.promotedCompat", "3.10.0"),
("poggit.pmapis.latest", "3.10.0"),
("poggit.pmapis.latestCompat", "3.0.0");


DELIMITER $$
CREATE FUNCTION IncRsrDlCnt(p_resourceId INT, p_ip VARCHAR(56))
    RETURNS INT
BEGIN
    DECLARE v_count INT;

    SELECT IFNULL((SELECT count FROM rsr_dl_ips WHERE resourceId = p_resourceId AND ip = p_ip),
                  0)
    INTO v_count;

    IF v_count > 0
    THEN
        UPDATE rsr_dl_ips SET latest = CURRENT_TIMESTAMP,
            count = v_count + 1 WHERE resourceId = p_resourceId AND ip = p_ip;
    ELSE
        UPDATE resources SET dlCount = dlCount + 1 WHERE resourceId = p_resourceId;
        INSERT INTO rsr_dl_ips (resourceId, ip) VALUES (p_resourceId, p_ip);
    END IF;

    RETURN v_count + 1;
END $$
CREATE FUNCTION KeepOnline(p_ip VARCHAR(40), p_uid INT UNSIGNED)
    RETURNS INT
BEGIN
    DECLARE cnt INT;

    IF p_uid != 0
    THEN
        UPDATE users SET lastLogin = CURRENT_TIMESTAMP WHERE uid = p_uid;
    END IF;

    INSERT INTO users_online (ip, lastOn)
    VALUES (p_ip, CURRENT_TIMESTAMP)
    ON DUPLICATE KEY UPDATE lastOn = CURRENT_TIMESTAMP;

    DELETE FROM users_online WHERE UNIX_TIMESTAMP() - UNIX_TIMESTAMP(lastOn) > 300;

    SELECT COUNT(*)
    INTO cnt FROM users_online;

    RETURN cnt;
END $$

-- for humans only
CREATE PROCEDURE BumpApi(IN api_id SMALLINT)
BEGIN
    CREATE TEMPORARY TABLE bumps (
        rid INT UNSIGNED
    );
    INSERT INTO bumps (rid)
    SELECT releaseId
    FROM (SELECT r.releaseId, r.flags & 4 outdated, MAX(k.id) max
          FROM releases r
                   LEFT JOIN release_spoons s ON r.releaseId = s.releaseId
                   INNER JOIN known_spoons k ON k.name = s.till
          GROUP BY r.releaseId
          HAVING outdated = 0 AND max < api_id) t;
    UPDATE releases SET flags = flags | 4 WHERE EXISTS(SELECT rid FROM bumps WHERE rid = releaseId);
    DROP TABLE bumps;
END $$
CREATE PROCEDURE MergeExtRef(IN to_name VARCHAR(255), IN from_pattern VARCHAR(255))
BEGIN
    DECLARE to_add BIGINT;

    SELECT SUM(cnt)
    INTO to_add FROM ext_refs WHERE srcDomain LIKE from_pattern;

    UPDATE ext_refs SET cnt = cnt + to_add WHERE srcDomain = to_name;

    DELETE FROM ext_refs WHERE srcDomain LIKE from_pattern;
END $$
DELIMITER ;
