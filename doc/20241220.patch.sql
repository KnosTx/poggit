-- Removes the single 'spoon' project, as spoons no longer supported (97b7030)
DELETE FROM projects where type = 3;
