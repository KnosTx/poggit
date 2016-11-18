DROP TABLE IF EXISTS users;
CREATE TABLE users (
    uid INT UNSIGNED PRIMARY KEY,
    name VARCHAR(255) UNIQUE,
    token VARCHAR(64),
    opts VARCHAR(16383) DEFAULT '{}'
);
DROP TABLE IF EXISTS repos;
CREATE TABLE repos (
    repoId INT UNSIGNED PRIMARY KEY,
    owner VARCHAR(256),
    name VARCHAR(256),
    private BIT(1),
    build BIT(1) DEFAULT 0,
    accessWith INT UNSIGNED REFERENCES users(uid),
    webhookId BIGINT UNSIGNED,
    webhookKey BINARY(8),
    KEY full_name (owner, name)
);
DROP TABLE IF EXISTS projects;
CREATE TABLE projects (
    projectId INT UNSIGNED PRIMARY KEY,
    repoId INT UNSIGNED REFERENCES repos(repoId),
    name VARCHAR(255),
    path VARCHAR(1000),
    type TINYINT UNSIGNED, -- Plugin = 0, Library = 1
    framework VARCHAR(100), -- default, nowhere
    lang BIT(1),
    UNIQUE KEY repo_proj (repoId, name)
);
DROP TABLE IF EXISTS resources;
CREATE TABLE resources (
    resourceId BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    type VARCHAR(100), -- phar, md, png, zip, etc.
    mimeType VARCHAR(100),
    created TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    accessFilters VARCHAR(8191) DEFAULT '[]',
    dlCount BIGINT DEFAULT 0,
    duration INT UNSIGNED,
    relMd BIGINT UNSIGNED DEFAULT NULL REFERENCES resources(resourceId)
) AUTO_INCREMENT=2;
INSERT INTO resources (resourceId, type, mimeType, accessFilters, dlCount, duration) VALUES
    (1, '', 'text/plain', '[]', 0, 315360000);
DROP TABLE IF EXISTS builds;
CREATE TABLE builds (
    buildId BIGINT UNSIGNED PRIMARY KEY,
    resourceId BIGINT UNSIGNED REFERENCES resources(resourceId),
    projectId INT REFERENCES projects(projectId),
    class TINYINT, -- Dev = 1, Beta = 2, Release = 3
    branch VARCHAR(255) DEFAULT 'master',
    cause VARCHAR(8191),
    internal INT, -- internal (project,class) build number, as opposed to global build number
    status VARCHAR(32767) DEFAULT '[]',
    created TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    triggerUser INT UNSIGNED DEFAULT 0, -- not necessarily REFERENCES users(uid), because may not have registered on Poggit yet
    KEY builds_by_project (projectId)
);
DROP TABLE IF EXISTS releases;
CREATE TABLE releases (
    releaseId INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255),
    shortDesc VARCHAR(1023) DEFAULT '',
    artifact BIGINT UNSIGNED REFERENCES resources(resourceId),
    projectId INT UNSIGNED REFERENCES projects(projectId),
    version VARCHAR(100), -- user-defined version ID, may duplicate
    type TINYINT UNSIGNED, -- Release = 1, Pre-release = 2
    description BIGINT UNSIGNED REFERENCES resources(resourceId),
    icon BIGINT UNSIGNED REFERENCES resources(resourceId),
    changelog BIGINT UNSIGNED REFERENCES resources(resourceId),
    license VARCHAR(100), -- name of license, or 'file'
    licenseRes BIGINT DEFAULT 1, -- resourceId of license, only set if `license` is set to 'file'
    flags SMALLINT DEFAULT 0, -- for example, featured
    creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    state TINYINT DEFAULT 0, -- not reviewed = 0, rough reviewed = 1, crowd reviewed = 2, final reviewed = 3
    KEY releases_by_project (projectId),
    KEY releases_by_name (name)
);
DROP TABLE IF EXISTS release_categories;
CREATE TABLE release_categories (
    projectId INT UNSIGNED REFERENCES projects(projectId),
    category SMALLINT UNSIGNED NOT NULL
);
DROP TABLE IF EXISTS release_keywords;
CREATE TABLE release_keywords (
    projectId INT UNSIGNED REFERENCES projects(projectId),
    word VARCHAR(100) NOT NULL,
);
DROP TABLE IF EXISTS release_spoons;
CREATE TABLE release_spoons (
    releaseId INT UNSIGNED REFERENCES releases(releaseId),
    spoonType VARCHAR(100) NOT NULL,
    version VARCHAR(100)
);
DROP TABLE IF EXISTS release_deps;
CREATE TABLE release_deps (
    releaseId INT UNSIGNED REFERENcES releases(releaseId),
    name VARCHAR(100) NOT NULL,
    version VARCHAR(100) DEFAULT NULL,
    projectId INT UNSIGNED
);
DROP TABLE IF EXISTS release_reviews;
CREATE TABLE release_reviews (
    releaseId INT UNSIGNED REFERENCES releases(releaseId),
    user INT UNSIGNED REFERENCES users(uid),
    criteria INT UNSIGNED,
    type TINYINT UNSIGNED, -- Official = 1, User = 2, Robot = 3
    cat TINYINT UNSIGNED, -- perspective: code? test?
    score SMALLINT UNSIGNED,
    message VARCHAR(8191) DEFAULT '',
    KEY reviews_by_plugin (releaseId),
    KEY reviews_by_plugin_user (releaseId, user),
    UNIQUE KEY reviews_by_plugin_user_criteria (releaseId, user, criteria)
);
DROP TABLE IF EXISTS release_watches;
CREATE TABLE release_watches (
    uid INT UNSIGNED REFERENCES users(uid),
    projectId INT UNSIGNED REFERENCES projects(projectId)
);
DROP TABLE IF EXISTS category_watches;
CREATE TABLE category_watches (
    uid INT UNSIGNED REFERENCES users(uid),
    category SMALLINT UNSIGNED NOT NULL
);
DROP TABLE IF EXISTS user_timeline;
CREATE TABLE user_timeline (
    eventId BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    uid INT UNSIGNED REFERENCES users(uid),
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    type SMALLINT UNSIGNED NOT NULL,
    details VARCHAR(8191)
);
