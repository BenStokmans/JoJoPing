import { List } from "@raycast/api";
import { useEffect, useState } from "react";
import { getPeers, NearbyPeer, RecentPeer } from "./api";

export default function Command() {
  const [nearby, setNearby] = useState<NearbyPeer[]>([]);
  const [recent, setRecent] = useState<RecentPeer[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getPeers()
      .then((r) => {
        setNearby(r.nearby);
        setRecent(r.recentlySeen);
      })
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }, []);

  if (err)
    return (
      <List searchBarPlaceholder="Error" filtering={false}>
        <List.EmptyView title={err} />
      </List>
    );
  return (
    <List isLoading={loading} searchBarPlaceholder="Search peers">
      <List.Section title="Nearby">
        {nearby.map((p) => (
          <List.Item key={p.id} title={p.displayName} subtitle="Online" />
        ))}
      </List.Section>
      {recent.length > 0 && (
        <List.Section title="Recently Seen">
          {recent.map((p) => (
            <List.Item key={p.id} title={p.displayName} subtitle={new Date(p.lastSeenISO).toLocaleString()} />
          ))}
        </List.Section>
      )}
    </List>
  );
}
