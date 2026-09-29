/**
 * agent-pet pi extension: registers /pet and drives the agent-pet CLI so the pet shows
 * only while pi is settled. Installed by symlink at ~/.pi/agent/extensions/agent-pet.ts.
 */

import { execFile } from "node:child_process";
import { accessSync, constants as fileSystemConstants } from "node:fs";
import { basename, delimiter as pathDelimiter, join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const PET_BINARY_NAME = "agent-pet";
const PET_COMMAND_NAME = "pet";
const PET_AGENT_NAME = "pi";
const UNENROLL_ARGUMENT = "off";
const SPRITE_TOKEN_PREFIX = "sprite:";
const CLI_TIMEOUT_MILLISECONDS = 2000;
const LOG_PREFIX = "[agent-pet]";
const INSTALL_HINT = `${PET_BINARY_NAME} is not on PATH. Run install.sh in the agent-pet repo first.`;

const PetSubcommand = {
	ENROLL: "on",
	UNENROLL: "off",
	SHOW: "show",
	HIDE: "hide",
	REMOVE: "remove",
} as const;

const PetMood = {
	READY: "ready",
	NEEDS_INPUT: "needsInput",
} as const;

const PetFlag = {
	AGENT: "--agent",
	SESSION: "--session",
	PROCESS_ID: "--pid",
	NICKNAME: "--nickname",
	ACCENT: "--accent",
	SPRITE: "--sprite",
	LABEL: "--label",
	MOOD: "--mood",
} as const;

const ACCENT_NAMES = new Set<string>(["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"]);

const INTERACTIVE_INPUT_SOURCE = "interactive";

type PetMoodName = (typeof PetMood)[keyof typeof PetMood];

interface PetEnrollmentOptions {
	nickname?: string;
	accent?: string;
	sprite?: string;
}

function logFailure(commandArguments: readonly string[], reason: string): void {
	console.error(`${LOG_PREFIX} ${PET_BINARY_NAME} ${commandArguments.join(" ")} failed: ${reason}`);
}

function describeError(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function isPetBinaryOnPath(): boolean {
	const searchPath = process.env.PATH;
	if (!searchPath) return false;
	for (const directory of searchPath.split(pathDelimiter)) {
		if (directory.length === 0) continue;
		try {
			accessSync(join(directory, PET_BINARY_NAME), fileSystemConstants.X_OK);
			return true;
		} catch {
			continue;
		}
	}
	return false;
}

function runPetCommandDetached(commandArguments: readonly string[]): void {
	try {
		execFile(PET_BINARY_NAME, [...commandArguments], { timeout: CLI_TIMEOUT_MILLISECONDS }, (error) => {
			if (error) logFailure(commandArguments, describeError(error));
		});
	} catch (error) {
		logFailure(commandArguments, describeError(error));
	}
}

function runPetCommandForOutput(commandArguments: readonly string[]): Promise<string | undefined> {
	return new Promise((resolve) => {
		try {
			execFile(
				PET_BINARY_NAME,
				[...commandArguments],
				{ timeout: CLI_TIMEOUT_MILLISECONDS },
				(error, standardOutput, standardError) => {
					if (error) {
						logFailure(commandArguments, describeError(error));
						resolve(undefined);
						return;
					}
					const firstLine = `${standardOutput}${standardError}`.trim().split("\n")[0];
					resolve(firstLine.length > 0 ? firstLine : undefined);
				},
			);
		} catch (error) {
			logFailure(commandArguments, describeError(error));
			resolve(undefined);
		}
	});
}

function parseEnrollmentArguments(argumentText: string): PetEnrollmentOptions {
	const tokens = argumentText.split(/\s+/).filter((token) => token.length > 0);
	const nicknameTokens: string[] = [];
	let accent: string | undefined;
	let sprite: string | undefined;

	for (const token of tokens) {
		const normalizedToken = token.toLowerCase();
		if (accent === undefined && ACCENT_NAMES.has(normalizedToken)) {
			accent = normalizedToken;
			continue;
		}
		if (sprite === undefined && normalizedToken.startsWith(SPRITE_TOKEN_PREFIX)) {
			const spriteName = token.slice(SPRITE_TOKEN_PREFIX.length);
			if (spriteName.length > 0) {
				sprite = spriteName;
				continue;
			}
		}
		nicknameTokens.push(token);
	}

	const nickname = nicknameTokens.join(" ");
	return {
		nickname: nickname.length > 0 ? nickname : undefined,
		accent,
		sprite,
	};
}

function buildEnrollmentArguments(
	sessionId: string,
	label: string,
	options: PetEnrollmentOptions,
): readonly string[] {
	const commandArguments: string[] = [
		PetSubcommand.ENROLL,
		PetFlag.AGENT,
		PET_AGENT_NAME,
		PetFlag.SESSION,
		sessionId,
		PetFlag.PROCESS_ID,
		String(process.pid),
	];
	if (options.nickname !== undefined) commandArguments.push(PetFlag.NICKNAME, options.nickname);
	if (options.accent !== undefined) commandArguments.push(PetFlag.ACCENT, options.accent);
	if (options.sprite !== undefined) commandArguments.push(PetFlag.SPRITE, options.sprite);
	commandArguments.push(PetFlag.LABEL, label);
	return commandArguments;
}

export default function (pi: ExtensionAPI) {
	let enrolledSessionId: string | undefined;

	const showPet = (mood: PetMoodName) => {
		if (enrolledSessionId === undefined) return;
		runPetCommandDetached([PetSubcommand.SHOW, PetFlag.SESSION, enrolledSessionId, PetFlag.MOOD, mood]);
	};

	const hidePet = () => {
		if (enrolledSessionId === undefined) return;
		runPetCommandDetached([PetSubcommand.HIDE, PetFlag.SESSION, enrolledSessionId]);
	};

	const announce = (context: ExtensionContext, message: string) => {
		if (!context.hasUI) return;
		context.ui.notify(message, "info");
	};

	pi.registerCommand(PET_COMMAND_NAME, {
		description: "Enroll this session's desktop pet (/pet [nickname] [accent] [sprite:name], /pet off)",
		handler: async (argumentText, context) => {
			if (!isPetBinaryOnPath()) {
				if (context.hasUI) context.ui.notify(INSTALL_HINT, "error");
				return;
			}

			const sessionId = context.sessionManager.getSessionId();

			if (argumentText.trim().toLowerCase() === UNENROLL_ARGUMENT) {
				enrolledSessionId = undefined;
				const unenrollOutput = await runPetCommandForOutput([
					PetSubcommand.UNENROLL,
					PetFlag.SESSION,
					sessionId,
				]);
				announce(context, unenrollOutput ?? "pet unenrolled for this session");
				return;
			}

			const label = pi.getSessionName() ?? basename(context.cwd);
			const enrollmentArguments = buildEnrollmentArguments(
				sessionId,
				label,
				parseEnrollmentArguments(argumentText),
			);
			const enrollOutput = await runPetCommandForOutput(enrollmentArguments);
			enrolledSessionId = sessionId;
			announce(context, enrollOutput ?? "pet enrolled for this session");
		},
	});

	pi.on("agent_settled", async () => {
		showPet(PetMood.READY);
	});

	pi.on("ui_prompt_start", async () => {
		showPet(PetMood.NEEDS_INPUT);
	});

	pi.on("ui_prompt_end", async () => {
		hidePet();
	});

	pi.on("input", async (event) => {
		if (event.source !== INTERACTIVE_INPUT_SOURCE) return;
		hidePet();
	});

	pi.on("tool_execution_start", async () => {
		hidePet();
	});

	pi.on("session_shutdown", async () => {
		if (enrolledSessionId === undefined) return;
		runPetCommandDetached([PetSubcommand.REMOVE, PetFlag.SESSION, enrolledSessionId]);
		enrolledSessionId = undefined;
	});
}
