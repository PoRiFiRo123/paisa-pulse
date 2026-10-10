DROP INDEX `budgets_category_idx`;--> statement-breakpoint
ALTER TABLE `budgets` ADD `period` text DEFAULT 'monthly' NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `budgets_category_period_idx` ON `budgets` (`category_id`,`period`);--> statement-breakpoint
ALTER TABLE `transactions` ADD `currency` text;--> statement-breakpoint
ALTER TABLE `transactions` ADD `original_amount` integer;