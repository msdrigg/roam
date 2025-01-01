import { DurableObject } from "cloudflare:workers";
import { APNSAuthKey, sendPushNotification } from "./apns";
import DiscordClient, { DiscordFile, DiscordMessage, Thread } from "./discord";

const DEFAULT_DURABLE_OBJECT_NAME = "apns";
export interface Env {
	ROAM_KV: KVNamespace;
	INTERNAL_DURABLE_OBJECT: DurableObjectNamespace<InternalDurableObject>;

	// Secrets
	DISCORD_TOKEN: string;
	DISCORD_HELP_CHANNEL: string;
	DISCORD_BOT_ID: string;
	DISCORD_GUILD_ID: string;

	APNS_KEY_ID: string;
	APNS_TEAM_ID: string;
	APNS_PRIVATE_KEY: string;

	API_KEY: string;

	// Vars
	ROAM_BUNDLE_ID: string;
}

type MessageRequest = {
	content: string;
	userId: string;
	apnsToken: string | null;
	installationInfo: InstallationInfo;
}

type InstallationInfo = {
	userId: string;
	buildVersion: string | null;
	osPlatform: string | null;
	osVersion: string | null;
	userLocale?: string | null;
}

async function checkAlerts(env: Env) {
	console.log("Checking alerts");

	let id = env.INTERNAL_DURABLE_OBJECT.idFromName("apns");
	let stub = env.INTERNAL_DURABLE_OBJECT.get(id);

	let { threads, latestMessageId } = await stub.consumeMessagesForApns();

	console.log(`Found ${threads.length} active threads since ${latestMessageId}. Last Message Ids: ${threads.map(thread => thread.lastMessageId)}`);

	let apnsKey: APNSAuthKey = {
		keyId: env.APNS_KEY_ID,
		teamId: env.APNS_TEAM_ID,
		privateKey: env.APNS_PRIVATE_KEY,
	}

	let pushesSent = 0;

	for (let thread of threads) {
		let stub = env.INTERNAL_DURABLE_OBJECT.get(env.INTERNAL_DURABLE_OBJECT.idFromName("apns"));
		let apnsToken = await stub.getApnsTokenForThread(thread.id);
		if (!apnsToken) {
			console.log(`No APNS token found for thread ${thread.id}`);
			continue;
		} else {
			console.log(`APNS token ${apnsToken} found for thread ${thread.id}`);
		}

		let messages = (await stub.getMessagesInThread(thread.id, latestMessageId))
			.filter((message) => message.type in [0, 19, 20, 21] && !isHidden(message) && !suppressNotification(message))
			.map((m) => normalizeMessage(m))

		console.log(`Found ${messages.length} notifiable messages in thread ${thread.id} since ${latestMessageId}. Last Message Ids: ${messages.map(message => message.id)}`);

		for (let message of messages) {
			if (pushesSent >= 5) {
				console.warn("Reached push limit, stopping");
				break;
			}
			if (message.author.id === env.DISCORD_BOT_ID) {
				console.log("Skipping message from bot");
				// Don't notify on messages from the bot
				continue;
			}
			try {
				console.log(`Sending push notification for message: ${message.content} to ${apnsToken} with bundle ID ${env.ROAM_BUNDLE_ID}`)
				await sendPushNotification("Message from roam", message.content, apnsKey, apnsToken, env.ROAM_BUNDLE_ID);
				pushesSent++;
			} catch (e) {
				console.error(`Error sending push notification: ${e}`);
			}
		}
	}
}

/// MARK: Durable Object

export class InternalDurableObject extends DurableObject {
	discordClient: DiscordClient;
	ROAM_KV: KVNamespace;

	constructor(state: DurableObjectState, env: Env) {
		super(state, env);
		this.discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);
		this.ROAM_KV = env.ROAM_KV;
	}

	async getApnsTokenForThread(threadId: string): Promise<string | null> {
		let apnsToken = this.tryGetCachedKey(`apnsToken:${threadId}`, undefined);
		return apnsToken;
	}

	async getApnsTokenForUser(userId: string): Promise<string | null> {
		let apnsToken = this.tryGetCachedKey(`apnsToken:${userId}`, undefined);
		return apnsToken;
	}

	async storeApnsToken(threadId: string, userId: string, apnsToken: string): Promise<void> {
		console.log(`Storing APNS token ${apnsToken} for thread ${threadId} and user ${userId}`);
		await this.ctx.storage.put(`apnsToken:${threadId}`, apnsToken);
		await this.ctx.storage.put(`apnsToken:${userId}`, apnsToken);
	}

	/// MARK: Discord Wrapper

	async getMessagesInThread(threadId: string, after: string | null): Promise<DiscordMessage[]> {
		let messages = await this.discordClient.getMessagesInThread(threadId, after);
		return messages;
	}

	async sendMessage(message: { content?: string, attachment?: DiscordFile }, userInfo: { apnsToken: string | null, userId: string, installationInfo?: InstallationInfo }): Promise<void> {
		const { content, attachment } = message;
		const { apnsToken, userId, installationInfo } = userInfo;

		console.log("Handling new message request", content, content, apnsToken, userId);

		let threadId = await this.getOrCreateThreadIdForUser(userId);

		if (apnsToken) {
			await this.storeApnsToken(threadId, userId, apnsToken);
		}

		if (content) {
			await this.discordClient.sendMessage(threadId, content)
		}

		if (attachment) {
			await this.discordClient.sendAttachment(threadId, attachment)
		}

		if (content || attachment) {
			await this.maybeSendDeviceInfo(userId, threadId, installationInfo, this.discordClient);
		}
	}

	private async maybeSendDeviceInfo(userId: string, threadId: string, installationInfo: InstallationInfo | undefined, discordClient: DiscordClient) {
		if (!installationInfo) {
			console.log("No installation info found");
			return;
		}

		let lastInstallationInfoSentText = await this.tryGetCachedKey(`deviceInfoSent:${userId}`, undefined);
		let lastInstallationInfoSent: InstallationInfo | null = null;
		try {
			if (lastInstallationInfoSentText) {
				lastInstallationInfoSent = JSON.parse(lastInstallationInfoSentText);
			}
		} catch (e) {
			console.error(`Error parsing installation info: ${e}`);
		}

		console.log(`Maybe sending device info: alreadySent=${!!lastInstallationInfoSent} blank=${!installationInfo}`);
		if (lastInstallationInfoSent?.buildVersion !== installationInfo.buildVersion || lastInstallationInfoSent?.osVersion !== installationInfo.osVersion || lastInstallationInfoSent?.osPlatform !== installationInfo.osPlatform || lastInstallationInfoSent?.userLocale !== installationInfo.userLocale) {
			console.log("Installation info changed, (re)sending");

			let { userId, buildVersion, osPlatform, osVersion, userLocale } = installationInfo;
			await discordClient.sendMessage(threadId, `:ninja:\n\n### Device info\n\n- **User ID**: ${userId}\n- **Build version**: ${buildVersion}\n- **OS platform**: ${osPlatform}\n- **OS version**: ${osVersion}\n- **User Locale**: ${userLocale}`);
			await this.ctx.storage.put(`deviceInfoSent:${userId}`, JSON.stringify(installationInfo));
		}
	}


	async sendAttachment(threadId: string, attachment: DiscordFile): Promise<void> {
		await this.discordClient.sendAttachment(threadId, attachment);
	}


	private async tryGetCachedKey(key: string, txn: DurableObjectTransaction | undefined): Promise<string | null> {
		if (txn) {
			let cachedValue = await txn.get(key);
			if (cachedValue) {
				return cachedValue as string;
			}
			let kvValue = await this.ROAM_KV.get(key);
			console.log(`Caching ${key} not found in DO storage with value ${kvValue}`);
			await txn.put(key, kvValue);
			return (kvValue as string) || null;
		} else {
			return await this.ctx.storage.transaction(async (txn) => {
				let cachedValue = await txn.get(key);
				if (cachedValue) {
					return cachedValue as string;
				}
				let kvValue = await this.ROAM_KV.get(key);
				console.log(`Caching ${key} not found in DO storage with value ${kvValue}`);
				await txn.put(key, kvValue);
				return (kvValue as string) || null;
			})
		}
	}


	/// MARK: External Functions

	async getThreadIdForUser(userId: string, txn?: DurableObjectTransaction): Promise<string | null> {
		let tid = await this.tryGetCachedKey(`threadId:${userId}`, txn);
		console.log(`Found existing thread ID: ${tid} for user ${userId}`)
		return tid || null
	}

	async getOrCreateThreadIdForUser(userId: string): Promise<string> {
		let result = await this.ctx.storage.transaction(async (txn) => {
			let threadId = await this.getThreadIdForUser(userId, txn);

			if (!threadId) {
				let newThreadId = await this.discordClient.createThread(`New message from ${userId}`, ":ninja:");
				await txn.put(`threadId:${userId}`, newThreadId);
				return newThreadId;
			} else {
				return threadId;
			}
		});

		return result;
	}

	async consumeMessagesForApns(): Promise<{ threads: Thread[], latestMessageId: string }> {
		let latestMessageId = await this.ctx.storage.get("latestMessageId") as string ?? null;

		let threads = await this.discordClient.getActiveThreadsUpdatedSince(latestMessageId ? String(latestMessageId) : null);

		let latestOverallMessageId = [latestMessageId, ...threads.map(thread => thread.lastMessageId)]
			.reduce((max, current) => max.localeCompare(current) > 0 ? max : current);

		await this.ctx.storage.put("latestMessageId", latestOverallMessageId);

		return { threads, latestMessageId: latestMessageId ? latestMessageId : "0" };
	}
}

export default {
	async fetch(request, env, _ctx): Promise<Response> {
		let pathSegments = new URL(request.url).pathname.split("/").filter(Boolean);
		let apiKeyHeader = request.headers.get("x-api-key");
		if (apiKeyHeader !== env.API_KEY) {
			return new Response("Unauthorized", { status: 401 });
		}

		if (pathSegments.length === 0) {
			return new Response("Hello, world!", { status: 200 });
		}

		let stub = env.INTERNAL_DURABLE_OBJECT.get(env.INTERNAL_DURABLE_OBJECT.idFromName(DEFAULT_DURABLE_OBJECT_NAME));

		if (pathSegments[0] === "messages") {
			let userId = pathSegments[1];
			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			let threadId = await stub.getThreadIdForUser(userId);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			let messages = (await stub.getMessagesInThread(threadId, after))
				.filter((message) => !isHidden(message))
				.map((m) => normalizeMessage(m))

			return new Response(JSON.stringify(messages), { status: 200 });
		}

		if (pathSegments[0] === "new-message") {
			let messageRequest = await request.json() as MessageRequest;
			let {
				content,
				apnsToken,
				userId,
				installationInfo,
			} = messageRequest;

			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			await stub.sendMessage({ content }, { apnsToken, userId, installationInfo });

			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "upload-diagnostics") {
			let diagnosticKey = pathSegments[1];

			if (!diagnosticKey) {
				return new Response("Bad request", { status: 400 });
			}
			// User ids are of the form "xxx-xxx-xxx"
			let userId = diagnosticKey.slice(0, 11);

			let data = await request.arrayBuffer();

			await stub.sendMessage({
				attachment: {
					name: "diagnostics.json",
					data,
					contentType: "application/json",
				}
			}, { apnsToken: null, userId });

			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "alert") {
			await checkAlerts(env);
			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "user-info") {
			let userId = pathSegments[1];
			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}


			let stub = env.INTERNAL_DURABLE_OBJECT.get(env.INTERNAL_DURABLE_OBJECT.idFromName("apns"));

			let threadId = await stub.getThreadIdForUser(userId);
			let apnsToken: string | null = null
			if (threadId) {
				apnsToken = await stub.getApnsTokenForThread(threadId);
			}
			let userApns = await stub.getApnsTokenForUser(userId);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			let messages: DiscordMessage[] | null = null;
			if (threadId) {
				messages = (await stub.getMessagesInThread(threadId, after))
					.filter((message) => !isHidden(message))
					.map((m) => normalizeMessage(m))
			}

			return new Response(JSON.stringify({ messages, threadId, apnsToken, userId, userApns }), { status: 200 });
		}

		if (pathSegments[0] === "thread-info") {
			let threadId = pathSegments[1];
			if (!threadId) {
				return new Response("Bad request", { status: 400 });
			}


			let stub = env.INTERNAL_DURABLE_OBJECT.get(env.INTERNAL_DURABLE_OBJECT.idFromName("apns"));

			let apnsToken: string | null = null
			if (threadId) {
				apnsToken = await stub.getApnsTokenForThread(threadId);
			}

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			let messages: DiscordMessage[] | null = null;
			if (threadId) {
				messages = (await stub.getMessagesInThread(threadId, after))
					.filter((message) => !isHidden(message))
					.map((m) => normalizeMessage(m))
			}

			return new Response(JSON.stringify({ messages, threadId, apnsToken }), { status: 200 });
		}

		return new Response("Not found", { status: 404 });
	},

	async scheduled(_event, env, _ctx) {
		console.log("Handling scheduled event")
		await checkAlerts(env);
	},
} satisfies ExportedHandler<Env>;

/// MARK: Helpers

const allowedMessages = new Set([0, 19, 20, 21]);

function suppressNotification(message: DiscordMessage): boolean {
	return message.content.startsWith(":cold:")
}

function isHidden(message: DiscordMessage): boolean {
	return !message.content || message.content.startsWith("!HiddenMessage") || message.content.startsWith(":ninja:") || !allowedMessages.has(message.type)
}

function normalizeMessage(message: DiscordMessage): DiscordMessage {
	if (message.content.startsWith(":cold:")) {
		message.content = message.content.slice(6);
	}

	return message;
}