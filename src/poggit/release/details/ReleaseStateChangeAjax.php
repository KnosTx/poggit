<?php

/*
 * Poggit
 *
 * Copyright (C) 2016-2018 Poggit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

namespace poggit\release\details;

use poggit\account\Session;
use poggit\Config;
use poggit\Meta;
use poggit\module\AjaxModule;
use poggit\release\Release;
use poggit\resource\ResourceManager;
use poggit\timeline\NewPluginUpdateTimeLineEvent;
use poggit\utils\internet\Curl;
use poggit\utils\internet\Mysql;

class ReleaseStateChangeAjax extends AjaxModule {
    protected function impl() {
        // read post fields
        $releaseId = (int) $this->param("relId", $_POST);
        if(!is_numeric($releaseId)) $this->errorBadRequest("relId should be numeric");
        $session = Session::getInstance();
        $user = $session->getName();
        if(isset($_POST["action"]) && $_POST["action"] === 'delete') {
            $relMeta = Mysql::query("SELECT rp.owner AS owner, rp.repoId as repoId, r.description AS description, r.state AS state, r.changelog AS changelog, r.licenseRes AS licRes FROM repos rp
                INNER JOIN projects p ON p.repoId = rp.repoId
                INNER JOIN releases r ON r.projectId = p.projectId
                WHERE r.releaseId = ?", "i", $releaseId);
            $writePerm = Curl::testPermission($relMeta[0]["repoId"], $session->getAccessToken(), $session->getName(), "push");
            if(($writePerm &&
                    ($relMeta[0]["state"] === Release::STATE_DRAFT || $relMeta[0]["state"] === Release::STATE_SUBMITTED)) ||
                (Meta::getAdmlv($user) === Meta::ADMLV_ADMIN && $relMeta[0]["state"] <= Release::STATE_SUBMITTED)) {
                Mysql::query("DELETE FROM releases WHERE releaseId = ?",
                    "i", $releaseId);
                // DELETE RESOURCES: description, changelog, licenseRes and resource entry
                $description = $relMeta[0]["description"];
                $changelog = $relMeta[0]["changelog"];
                $licenseRes = $relMeta[0]["licRes"];

                $desc = ResourceManager::getInstance()->getResource($description);
                unlink($desc);
                if($changelog) {
                    $change = ResourceManager::getInstance()->getResource($changelog);
                    unlink($change);
                }
                if($licenseRes) {
                    $licenseResPath = ResourceManager::getInstance()->getResource($licenseRes);
                    unlink($licenseResPath);
                }

                Mysql::query("DELETE FROM resources WHERE resourceId IN (?, ?, ?)", "iii", $description, $changelog, $licenseRes);
                Meta::getLog()->w("$user deleted releaseId $releaseId");
                echo json_encode([
                    "state" => -1
                ]);
            } else {
                $this->errorAccessDenied("You cannot delete this release.");
            }
        } else {
            if(Meta::getAdmlv($user) < Meta::ADMLV_MODERATOR) $this->errorAccessDenied();
            $newState = $this->param("state");
            if(!is_numeric($newState)) $this->errorBadRequest("state must be numeric");
            $newState = (int) $newState;

            $info = Mysql::query("SELECT state, projectId FROM releases WHERE releaseId = ?", "i", $releaseId);
            if(!isset($info[0])) $this->errorNotFound(true);
            $oldState = (int) $info[0]["state"];
            $projectId = (int) $info[0]["projectId"];
            /** @noinspection UnnecessaryParenthesesInspection */
            $updateTime = ($oldState >= Config::MIN_PUBLIC_RELEASE_STATE) === ($newState >= Config::MIN_PUBLIC_RELEASE_STATE) ?
                "" : ", updateTime = CURRENT_TIMESTAMP";
            Mysql::query("UPDATE releases SET state = ? {$updateTime} WHERE releaseId = ?", "ii", $newState, $releaseId);

            $maxRelId = (int) Mysql::query("SELECT IFNULL(MAX(releaseId), -1) id FROM releases WHERE projectId = ? AND state >= ?", "ii", $projectId, Release::STATE_VOTED)[0]["id"];
            $obsoleteFlag = Release::FLAG_OBSOLETE;
            if($maxRelId !== -1) {
                Mysql::query("UPDATE releases SET flags = CASE
                WHEN releaseId >= ? THEN flags & (~?)
                ELSE flags | ?
            END WHERE projectId = ?", "iiii", $maxRelId, $obsoleteFlag, $obsoleteFlag, $projectId);
            }

            if($oldState < Config::MIN_PUBLIC_RELEASE_STATE && $newState >= Config::MIN_PUBLIC_RELEASE_STATE){
                self::notifyRelease($releaseId, $oldState, $newState, "@$user");
            }


            Meta::getLog()->w("$user changed releaseId $releaseId from state $oldState to $newState. Head version is now release($maxRelId)");
            echo json_encode([
                "state" => $newState,
            ]);
        }
    }

    const ISSUE_COMMENT_PREFIX = "repos/poggit/plugins/issues/";
    const MASTER_ISSUE = 16;

    public static function notifyRelease(int $releaseId, int $oldState, int $newState, string $changedBy = "Community") {
        $event = new NewPluginUpdateTimeLineEvent();
        $event->releaseId = $releaseId;
        $event->oldState = $oldState;
        $event->newState = $newState;
        $event->changedBy = $changedBy;
        $event->dispatch();

        $result = Mysql::query("SELECT r.name, version, r3.owner,
            (SELECT COUNT(*) FROM releases r2 WHERE r.projectId = r2.projectId AND r.releaseId > r2.releaseId) isLatest,
            (SELECT category FROM release_categories rc WHERE rc.projectId = r.projectId AND rc.isMainCategory LIMIT 1) mainCat
            FROM releases r INNER JOIN projects p ON r.projectId = p.projectId INNER JOIN repos r3 ON p.repoId = r3.repoId
            WHERE releaseId = ?", "i", $releaseId)[0];

        $isLatest = (int) $result["isLatest"];
        $name = $result["name"];
        $version = $result["version"];
        $owner = $result["owner"];
        $mainCatName = Release::$CATEGORIES[$result["mainCat"]];
        $newStateName = Release::$STATE_ID_TO_HUMAN[$newState];

        $issues = [];
        if($isLatest === 0){
            $issues[] = self::MASTER_ISSUE;
            $issues[] = $result["mainCat"];
        }

        foreach($issues as $issueId){
            Curl::ghApiPost(self::ISSUE_COMMENT_PREFIX . $issueId . "/comments", [
                "body" => "**A new {$mainCatName} plugin has been released!**\n\n**[{$name} v{$version}](https://poggit.pmmp.io/p/{$name}/{$version})** by @{$owner} has been **$newStateName** by {$changedBy} on Poggit. Don't forget to [review](https://poggit.pmmp.io/p/{$name}/{$version}#review-anchor) it!"
            ], Meta::getBotToken());
        }
    }
}
