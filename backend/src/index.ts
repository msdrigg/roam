import { DurableObject } from "cloudflare:workers";
import { APNSAuthKey, sendPushNotification } from "./apns";
import DiscordClient, { DiscordFile, DiscordMessage, Thread } from "./discord";

export interface Env {
	ROAM_KV: KVNamespace;
	APNS_DURABLE_OBJECT: DurableObjectNamespace<InternalDurableObject>;

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
	title: string;
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
}

async function maybeSendDeviceInfo(env: Env, userId: string, threadId: string, installationInfo: InstallationInfo | undefined, discordClient: DiscordClient) {
	if (!installationInfo) {
		console.log("No installation info found");
		return;
	}

	let lastInstallationInfoSentText = await env.ROAM_KV.get(`deviceInfoSent:${userId}`);
	let lastInstallationInfoSent: InstallationInfo | null = null;
	try {
		if (lastInstallationInfoSentText) {
			lastInstallationInfoSent = JSON.parse(lastInstallationInfoSentText);
		}
	} catch (e) {
		console.error(`Error parsing installation info: ${e}`);
	}

	console.log(`Maybe sending device info: alreadySent=${!!lastInstallationInfoSent} blank=${!installationInfo}`);
	if (lastInstallationInfoSent?.buildVersion !== installationInfo.buildVersion || lastInstallationInfoSent?.osVersion !== installationInfo.osVersion || lastInstallationInfoSent?.osPlatform !== installationInfo.osPlatform) {
		console.log("Installation info changed, (re)sending");

		let { userId, buildVersion, osPlatform, osVersion } = installationInfo;
		await discordClient.sendMessage(threadId, `:ninja:\n\n**Device info**:\n- User ID: ${userId}\n- Build version: ${buildVersion}\n- OS platform: ${osPlatform}\n- OS version: ${osVersion}`);
		await env.ROAM_KV.put(`deviceInfoSent:${userId}`, JSON.stringify(installationInfo));
	}
}

async function sendMessage(message: {
	title?: string,
	content?: string,
	attachment?: DiscordFile,
},
	userInfo: {
		apnsToken: string | null,
		userId: string,
		installationInfo?: InstallationInfo,
	},
	env: Env, discordClient: DiscordClient): Promise<void> {
	const { title, content, attachment: attachment } = message;
	const { apnsToken, userId, installationInfo } = userInfo;

	console.log("Handling new message request", title, content, apnsToken, userId);

	let stub = env.APNS_DURABLE_OBJECT.get(env.APNS_DURABLE_OBJECT.idFromName("apns"));
	let threadId = await stub.getOrCreateThreadIdForUser(userId);

	if (apnsToken) {
		await stub.storeApnsToken(threadId, userId, apnsToken);
	}

	if (content) {
		await discordClient.sendMessage(threadId, content)
	}

	if (attachment) {
		await discordClient.sendAttachment(threadId, attachment)
	}

	if (content || attachment) {
		await maybeSendDeviceInfo(env, userId, threadId, installationInfo, discordClient);
	}
}

async function checkAlerts(env: Env) {
	console.log("Checking alerts");
	let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

	let id = env.APNS_DURABLE_OBJECT.idFromName("apns");
	let stub = env.APNS_DURABLE_OBJECT.get(id);

	let { threads, latestMessageId } = await stub.consumeMessagesForApns();

	console.log(`Found ${threads.length} active threads since ${latestMessageId}. Last Message Ids: ${threads.map(thread => thread.lastMessageId)}`);

	let apnsKey: APNSAuthKey = {
		keyId: env.APNS_KEY_ID,
		teamId: env.APNS_TEAM_ID,
		privateKey: env.APNS_PRIVATE_KEY,
	}

	let pushesSent = 0;

	for (let thread of threads) {
		let stub = env.APNS_DURABLE_OBJECT.get(env.APNS_DURABLE_OBJECT.idFromName("apns"));
		let apnsToken = await stub.getApnsTokenForThread(thread.id);
		if (!apnsToken) {
			console.log(`No APNS token found for thread ${thread.id}`);
			continue;
		} else {
			console.log(`APNS token ${apnsToken} found for thread ${thread.id}`);
		}

		let messages = (await discordClient.getMessagesInThread(thread.id, latestMessageId))
			.filter((message) => message.content && message.type in [0, 19, 20, 21] && !message.content.startsWith("!HiddenMessage"));

		console.log(`Found ${messages.length} messages in thread ${thread.id} since ${latestMessageId}. Last Message Ids: ${messages.map(message => message.id)}`);

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

export class InternalDurableObject extends DurableObject {
	discordClient: DiscordClient;
	ROAM_KV: KVNamespace;

	constructor(state: DurableObjectState, env: Env) {
		super(state, env);
		this.discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);
		this.ROAM_KV = env.ROAM_KV;
	}

	async getApnsTokenForThread(threadId: string): Promise<string | null> {
		let apnsToken = await this.ctx.storage.get(`apnsToken:${threadId}`);
		console.log(`Existing APNS token: ${apnsToken}`)

		if (apnsToken) {
			return apnsToken as string;
		}
		let newApnsToken = await this.ROAM_KV.get(`apnsToken:${threadId}`);
		if (!newApnsToken) {
			return null;
		}

		await this.ctx.storage.put(`apnsToken:${threadId}`, newApnsToken);
		return newApnsToken;
	}

	async storeApnsToken(threadId: string, userId: string, apnsToken: string): Promise<void> {
		await this.ctx.storage.put(`apnsToken:${threadId}`, apnsToken);
		await this.ctx.storage.put(`apnsToken:${userId}`, apnsToken);
	}

	async getThreadIdForUser(userId: string): Promise<string | null> {
		let threadId = await this.ctx.storage.get(`threadId:${userId}`);
		console.log(`Existing thread ID: ${threadId}`)

		if (threadId) {
			return threadId as string;
		}
		let newThreadId = await this.ROAM_KV.get(`threadId:${userId}`);
		if (!newThreadId) {
			return null;
		}

		await this.ctx.storage.put(`threadId:${userId}`, newThreadId);
		return newThreadId;
	}

	async getOrCreateThreadIdForUser(userId: string): Promise<string> {
		let threadId = await this.ctx.storage.get(`threadId:${userId}`);
		console.log(`Existing thread ID: ${threadId}`)

		if (threadId) {
			return threadId as string;
		}
		let newThreadId = await this.ROAM_KV.get(`threadId:${userId}`);
		if (!newThreadId) {
			newThreadId = await this.discordClient.createThread(`New message from ${userId}`, ":ninja:");
		}

		await this.ctx.storage.put(`threadId:${userId}`, newThreadId);
		return newThreadId;
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

		let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

		if (pathSegments.length === 0) {
			return new Response("Hello, world!", { status: 200 });
		}

		if (pathSegments[0] === "messages") {
			let userId = pathSegments[1];
			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			let stub = env.APNS_DURABLE_OBJECT.get(env.APNS_DURABLE_OBJECT.idFromName("apns"));
			let threadId = await stub.getThreadIdForUser(userId);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			let messages = (await discordClient.getMessagesInThread(threadId, after))
				.filter((message) => !isHidden(message));

			return new Response(JSON.stringify(messages), { status: 200 });
		}

		if (pathSegments[0] === "new-message") {
			let messageRequest = await request.json() as MessageRequest;
			let {
				title,
				content,
				apnsToken,
				userId,
				installationInfo,
			} = messageRequest;

			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			await sendMessage({ title, content }, { apnsToken, userId, installationInfo }, env, discordClient);

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

			await sendMessage({
				attachment: {
					name: "diagnostics.json",
					data,
					contentType: "application/json"
				}
			}, { apnsToken: null, userId }, env, discordClient);

			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "alert") {
			await checkAlerts(env);
			return new Response("OK", { status: 200 });
		}

		return new Response("Not found", { status: 404 });
	},

	async scheduled(_event, env, _ctx) {
		console.log("Handling scheduled event")
		await checkAlerts(env);
	},
} satisfies ExportedHandler<Env>;

const allowedMessages = new Set([0, 19, 20, 21]);

function isHidden(message: DiscordMessage): boolean {
	return !message.content || message.content.startsWith("!HiddenMessage") || message.content.startsWith(":ninja:") || !allowedMessages.has(message.type)
}
