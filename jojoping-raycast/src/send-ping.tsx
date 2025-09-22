import { Action, ActionPanel, Form, showHUD, useNavigation } from "@raycast/api";
import { useEffect, useState } from "react";
import { getPeers, sendPing, NearbyPeer } from "./api";

export default function Command() {
  const nav = useNavigation();
  const [peers, setPeers] = useState<NearbyPeer[]>([]);

  useEffect(() => {
    getPeers().then((r) => setPeers(r.nearby));
  }, []);

  async function onSubmit(values: { to: string; note?: string }) {
    const res = await sendPing(values.to, values.note);
    await showHUD(res.delivered ? "Ping delivered" : "Ping failed");
    nav.pop();
  }

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Send Ping" onSubmit={onSubmit} />
        </ActionPanel>
      }
    >
      <Form.Dropdown id="to" title="Peer">
        {peers.map((p) => (
          <Form.Dropdown.Item key={p.id} value={p.id} title={p.displayName} />
        ))}
      </Form.Dropdown>
      <Form.TextArea id="note" title="Note" placeholder="Optional note" enableMarkdown={false} autoFocus />
    </Form>
  );
}
