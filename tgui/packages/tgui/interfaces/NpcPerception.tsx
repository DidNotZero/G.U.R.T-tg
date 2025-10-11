import { useBackend } from '../backend';
import { Button, LabeledList, Section, NumberInput, Box, Table, Collapsible } from 'tgui-core/components';
import { Window } from '../layouts';

type Config = {
  enabled: boolean;
  range: number;
  use_los: boolean;
  max_entities: number;
  hearing_local_radius: number;
  speech_queue_max: number;
  tick_skip: number;
  across_z_default: boolean;
  ttl_seconds: number;
  overlay_realtime: boolean;
  overlay_max_npcs: number;
};

type Data = {
  config: Config;
  overlay_enabled: boolean;
  timer_active: boolean;
  crew_count: number;
  hazards?: Array<{
    mob: string;
    ref: string;
    count: number;
    hazards: Array<{ x: number; y: number; z: number; age_s: number; confidence: number }>;
  }>;
};

export const NpcPerception = () => {
  const { data, act } = useBackend<Data>();
  const cfg = data.config || ({} as Config);
  const set = (key: keyof Config, value: any) => act('set_config', { key, value });
  return (
    <Window width={640} height={640} title="NPC Perception">
      <Window.Content scrollable>
        <Section title="Status" buttons={
          <>
            <Button
              content={data.overlay_enabled ? 'Overlay: ON' : 'Overlay: OFF'}
              color={data.overlay_enabled ? 'good' : 'default'}
              onClick={() => act('toggle_overlay', { enable: data.overlay_enabled ? 0 : 1 })}
            />
            <Button content="Refresh" onClick={() => act('refresh', { limit: cfg.overlay_max_npcs })} />
            <Button content="Ensure Timer" onClick={() => act('ensure_timer')} />
          </>
        }>
          <LabeledList>
            <LabeledList.Item label="Crew Tracked">{data.crew_count}</LabeledList.Item>
            <LabeledList.Item label="Timer Active">{data.timer_active ? 'Yes' : 'No'}</LabeledList.Item>
          </LabeledList>
        </Section>

        <Section title="Profiling">
          <Box mb={1}>
            Print recent Sense() times and counters for up to N NPCs in admin chat.
          </Box>
          <Button onClick={() => act('profile', { ticks: 10 })}>Profile 10</Button>
          <Button onClick={() => act('profile', { ticks: 25 })} ml={1}>Profile 25</Button>
          <Button onClick={() => act('profile', { ticks: 50 })} ml={1}>Profile 50</Button>
        </Section>

        <Section title={`Hazards (${(data.hazards?.length ?? 0)} NPCs)`}>
          {(data.hazards?.length ?? 0) === 0 && (
            <Box color="label">No hazard entries found for NPC crew.</Box>
          )}
          {data.hazards?.map((h) => (
            <Collapsible key={h.ref} title={`${h.mob} — hazards: ${h.count}`}>
              <Table>
                <Table.Row header>
                  <Table.Cell>X</Table.Cell>
                  <Table.Cell>Y</Table.Cell>
                  <Table.Cell>Z</Table.Cell>
                  <Table.Cell>Age (s)</Table.Cell>
                  <Table.Cell>Conf</Table.Cell>
                </Table.Row>
                {h.hazards.map((e, idx) => (
                  <Table.Row key={idx}>
                    <Table.Cell>{e.x}</Table.Cell>
                    <Table.Cell>{e.y}</Table.Cell>
                    <Table.Cell>{e.z}</Table.Cell>
                    <Table.Cell>{e.age_s}</Table.Cell>
                    <Table.Cell>{Math.round((e.confidence ?? 0) * 100) / 100}</Table.Cell>
                  </Table.Row>
                ))}
              </Table>
            </Collapsible>
          ))}
        </Section>

        <Section title="Configuration">
          <LabeledList>
            <LabeledList.Item label="Enabled">
              <Button.Checkbox checked={cfg.enabled} onClick={() => set('enabled', cfg.enabled ? 0 : 1)}>
                {cfg.enabled ? 'On' : 'Off'}
              </Button.Checkbox>
            </LabeledList.Item>
            <LabeledList.Item label="Range">
              <NumberInput value={cfg.range} minValue={1} maxValue={32} onChange={(v) => set('range', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Use LOS">
              <Button.Checkbox checked={cfg.use_los} onClick={() => set('use_los', cfg.use_los ? 0 : 1)}>
                {cfg.use_los ? 'On' : 'Off'}
              </Button.Checkbox>
            </LabeledList.Item>
            <LabeledList.Item label="Max Entities/Cycle">
              <NumberInput value={cfg.max_entities} minValue={1} maxValue={500} onChange={(v) => set('max_entities', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Hearing Radius">
              <NumberInput value={cfg.hearing_local_radius} minValue={0} maxValue={32} onChange={(v) => set('hearing_local_radius', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Speech Queue Max">
              <NumberInput value={cfg.speech_queue_max} minValue={1} maxValue={200} onChange={(v) => set('speech_queue_max', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Tick Skip">
              <NumberInput value={cfg.tick_skip} minValue={0} maxValue={10} onChange={(v) => set('tick_skip', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Across-Z Default">
              <Button.Checkbox
                checked={cfg.across_z_default}
                onClick={() => set('across_z_default', cfg.across_z_default ? 0 : 1)}
              >
                {cfg.across_z_default ? 'On' : 'Off'}
              </Button.Checkbox>
            </LabeledList.Item>
            <LabeledList.Item label="TTL (s)">
              <NumberInput value={cfg.ttl_seconds} minValue={5} maxValue={600} onChange={(v) => set('ttl_seconds', v)} />
            </LabeledList.Item>
            <LabeledList.Item label="Overlay Realtime Logs">
              <Button.Checkbox
                checked={cfg.overlay_realtime}
                onClick={() => set('overlay_realtime', cfg.overlay_realtime ? 0 : 1)}
              >
                {cfg.overlay_realtime ? 'On' : 'Off'}
              </Button.Checkbox>
            </LabeledList.Item>
            <LabeledList.Item label="Overlay Max NPCs">
              <NumberInput value={cfg.overlay_max_npcs} minValue={1} maxValue={200} onChange={(v) => set('overlay_max_npcs', v)} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
