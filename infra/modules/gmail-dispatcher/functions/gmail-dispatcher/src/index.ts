interface PubSubMessage {
  data: string;
  message_id: string;
  publish_time: string;
}

interface GmailNotification {
  emailAddress: string;
  historyId: string;
}

export const handlePubSub = async (cloudEvent: PubSubMessage): Promise<void> => {
  const payload = Buffer.from(cloudEvent.data, "base64").toString("utf-8");
  const data: GmailNotification = JSON.parse(payload);

  console.log(
    JSON.stringify({
      severity: "INFO",
      message: "Gmail notification received",
      emailAddress: data.emailAddress,
      historyId: data.historyId,
      messageId: cloudEvent.message_id,
      publishTime: cloudEvent.publish_time,
    }),
  );
};
