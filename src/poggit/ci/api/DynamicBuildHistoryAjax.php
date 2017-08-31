<?php

/*
 *
 * poggit
 *
 * Copyright (C) 2017 SOFe
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 */

declare(strict_types=1);

namespace poggit\ci\api;

use poggit\ci\builder\ProjectBuilder;
use poggit\module\AjaxModule;
use poggit\resource\ResourceManager;
use poggit\utils\internet\Mysql;

class DynamicBuildHistoryAjax extends AjaxModule {
    public function getName(): string {
        return "build.history.new";
    }

    protected function needLogin(): bool {
        return false;
    }

    protected function impl() {
        $projectId = (int) $this->param("projectId");
        $branch = $this->param("branch");
        $isPr = isset($_REQUEST["pr"]);
        $acceptedClass = $isPr ? ProjectBuilder::BUILD_CLASS_PR : ProjectBuilder::BUILD_CLASS_DEV;
        $branchColumn = $isPr ? "substring_index(substring_index(cause, '\"prNumber\":',-1), ',', 1)" : "branch";
        $count = (int) $this->param("count");
        if($count <= 0) $this->errorBadRequest("count must be a positive integer");
        $lt = (int) $this->param("lt");
        if($lt === 0 || $lt < -1) $this->errorBadRequest("end must be -1 or positive integer");

        $rows = array_map(function(array $input) use($isPr){
            $row = (object) $input;
            $row->cause = json_decode($row->cause);
            $row->date = (int) $row->date;
            if($isPr) $row->branch = (int) $row->branch;
            $row->virions = [];
            $row->lintCount = (int) ($row->lintCount ?? 0);
            $row->worstLint = (int) ($row->worstLint ?? 0);
            if($row->libs !== null){
                foreach(explode(",", $row->libs ?? "") as $lib){
                    $versions = explode(":", $lib, 2);
                    $row->virions[$versions[0]] = $versions[1];
                }
            }
            $row->dlSize = filesize(ResourceManager::pathTo($row->resourceId, "phar"));
            unset($row->libs);
            return $row;
        }, Mysql::query("SELECT
                builds.buildId, class, internal, UNIX_TIMESTAMP(created) date, resourceId, $branchColumn branch, sha, cause, main, path,
                bs.cnt lintCount, bs.maxLevel worstLint,
                virion_builds.version virionVersion, virion_builds.api virionApi,
                (SELECT GROUP_CONCAT(CONCAT(vp.name, ':', vvb.version) SEPARATOR ',') FROM virion_usages
                    INNER JOIN builds vb ON virion_usages.virionBuild = vb.buildId
                    INNER JOIN virion_builds vvb ON vvb.buildId = vb.buildId
                    INNER JOIN projects vp ON vp.projectId = vb.projectId
                    WHERE virion_usages.userBuild = builds.buildId) libs
            FROM builds
                LEFT JOIN (SELECT buildId, COUNT(*) cnt, MAX(level) maxLevel FROM builds_statuses GROUP BY buildId) bs
                    ON bs.buildId = builds.buildId
                LEFT JOIN virion_builds ON builds.buildId = virion_builds.buildId
            WHERE projectId = ? AND (? = -1 OR internal < ?) AND class = ?
                AND (? IN ($branchColumn, 'special:dev', 'special:pr'))
            ORDER BY buildId DESC LIMIT $count", "iiiis", $projectId, $lt, $lt, $acceptedClass, $branch));

        echo json_encode($rows);
    }
}
