CREATE TABLE `budgets` (
	`id` text PRIMARY KEY NOT NULL,
	`category_id` text,
	`amount` integer NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`category_id`) REFERENCES `categories`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "budgets_amount_positive" CHECK("budgets"."amount" > 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `budgets_category_idx` ON `budgets` (`category_id`);--> statement-breakpoint
CREATE TABLE `recurring_rules` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`amount` integer NOT NULL,
	`account_id` text NOT NULL,
	`to_account_id` text,
	`category_id` text,
	`payee` text,
	`note` text,
	`frequency` text NOT NULL,
	`interval` integer DEFAULT 1 NOT NULL,
	`start_at` integer NOT NULL,
	`next_at` integer NOT NULL,
	`end_at` integer,
	`paused_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`to_account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`category_id`) REFERENCES `categories`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "recurring_amount_positive" CHECK("recurring_rules"."amount" > 0),
	CONSTRAINT "recurring_interval_positive" CHECK("recurring_rules"."interval" >= 1)
);
--> statement-breakpoint
CREATE INDEX `recurring_next_at_idx` ON `recurring_rules` (`next_at`);--> statement-breakpoint
CREATE TABLE `saved_filters` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`filters` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
ALTER TABLE `transactions` ADD `recurring_id` text REFERENCES recurring_rules(id);--> statement-breakpoint
CREATE INDEX `transactions_recurring_idx` ON `transactions` (`recurring_id`);