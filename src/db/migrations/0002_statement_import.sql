CREATE TABLE `import_batches` (
	`id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`file_name` text NOT NULL,
	`template` text,
	`count` integer NOT NULL,
	`created_at` integer NOT NULL,
	`undone_at` integer,
	FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `transactions` ADD `import_batch_id` text;--> statement-breakpoint
ALTER TABLE `transactions` ADD `external_id` text;--> statement-breakpoint
CREATE INDEX `transactions_import_batch_idx` ON `transactions` (`import_batch_id`);--> statement-breakpoint
CREATE INDEX `transactions_external_idx` ON `transactions` (`account_id`,`external_id`);