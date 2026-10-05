UPDATE "docurba_private"."analytics_events" SET
"user_id" = md5("user_id"::text)::uuid;

UPDATE "docurba_private"."doc_frise_events" SET
"archived_by_id" = md5("archived_by_id"::text)::uuid,
"profile_id" = md5("profile_id"::text)::uuid;

UPDATE "docurba_private"."prescriptions" SET
"user_id" = md5("user_id"::text)::uuid,
"email" = 'user+' || left(md5("email"), 16) || '@anon.invalid';

UPDATE "docurba_private"."procedures" SET
"owner_id" = md5("owner_id"::text)::uuid,
"last_updated_by_id" = md5("last_updated_by_id"::text)::uuid;

UPDATE "docurba_private"."procedures_validations" SET
"profile_id" = md5("profile_id"::text)::uuid;

UPDATE "docurba_private"."profiles" SET
"user_id" = md5("user_id"::text)::uuid,
"email" = 'user+' || left(md5("email"), 16) || '@anon.invalid',
"firstname" = 'Prénom ' || left(md5("email"), 8),
"lastname" = 'Nom ' || left(md5("email"), 8),
"tel" = NULL;

UPDATE "docurba_private"."projects" SET
"owner" = md5("owner"::text)::uuid;

UPDATE "docurba_private"."projects_sharing" SET
"user_email" = 'user+' || left(md5("user_email"), 16) || '@anon.invalid',
"shared_by" = md5("shared_by"::text)::uuid;

UPDATE "docurba_private"."surveys_proceduresurvey" SET
"respondant_id" = md5("respondant_id"::text)::uuid;
