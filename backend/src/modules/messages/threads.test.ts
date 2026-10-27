import { MessageStatus } from "@prisma/client";
import { summarizeThreads, type ThreadableMessage, type ThreadableUser } from "./threads.js";

const ME = "user-me";
const ALICE = "user-alice";
const BOB = "user-bob";

function message(overrides: Partial<ThreadableMessage> & Pick<ThreadableMessage, "id">): ThreadableMessage {
  return {
    senderId: ALICE,
    receiverId: ME,
    status: MessageStatus.SENT,
    createdAt: new Date("2026-09-11T10:00:00.000Z"),
    ...overrides,
  };
}

const users = new Map<string, ThreadableUser>([
  [ALICE, { id: ALICE, displayName: "Alice", phoneNumber: "+8801700000001" }],
  [BOB, { id: BOB, displayName: null, phoneNumber: "+8801700000002" }],
]);

describe("summarizeThreads", () => {
  test("returns one summary per counterpart with the newest message as last", () => {
    const messages = [
      message({ id: "a-new", senderId: ME, receiverId: ALICE, status: MessageStatus.READ, createdAt: new Date("2026-09-11T12:00:00.000Z") }),
      message({ id: "b-old", senderId: BOB, receiverId: ME, status: MessageStatus.DELIVERED, createdAt: new Date("2026-09-11T09:00:00.000Z") }),
      message({ id: "a-old", senderId: ALICE, receiverId: ME, createdAt: new Date("2026-09-11T08:00:00.000Z") }),
    ];

    const threads = summarizeThreads(messages, users, ME);

    expect(threads).toHaveLength(2);
    const alice = threads.find((t) => t.counterpartId === ALICE)!;
    expect(alice.lastMessageId).toBe("a-new");
    expect(alice.lastMessageMine).toBe(true);
    expect(alice.counterpartName).toBe("Alice");
    expect(alice.lastMessageAt).toEqual(new Date("2026-09-11T12:00:00.000Z"));
  });

  test("counts only received messages that are not READ as unread", () => {
    const messages = [
      message({ id: "1", senderId: ALICE, receiverId: ME, status: MessageStatus.SENT }),
      message({ id: "2", senderId: ALICE, receiverId: ME, status: MessageStatus.DELIVERED }),
      message({ id: "3", senderId: ALICE, receiverId: ME, status: MessageStatus.READ }),
      message({ id: "4", senderId: ME, receiverId: ALICE, status: MessageStatus.SENT }),
    ];

    const threads = summarizeThreads(messages, users, ME);

    expect(threads).toHaveLength(1);
    expect(threads[0].unreadCount).toBe(2);
  });

  test("falls back to phoneNumber when displayName is missing", () => {
    const threads = summarizeThreads([message({ id: "b", senderId: BOB, receiverId: ME })], users, ME);
    expect(threads[0].counterpartName).toBe("+8801700000002");
  });

  test("returns an empty list for no messages", () => {
    expect(summarizeThreads([], users, ME)).toEqual([]);
  });
});
