import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Dropdown,
  Icon,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Row = {
  id: string;
  name: string;
  state: 'normal' | 'alert' | 'critical' | string;
  time_in_state_s: number;
  ehp_rounded: number;
  alarm_nearby: boolean;
  last_reason_code: string;
  last_reason_age_s: number;
  tick_skip: number;
  speech_radius: number;
};

type Data = {
  alert_level: string | null;
  evac_enabled: boolean;
  rows: Row[];
};

const STATE_COLORS: Record<string, string> = {
  normal: 'good',
  alert: 'average',
  critical: 'bad',
};

export const NpcAIState = () => {
  const { data, act } = useBackend<Data>();
  const { alert_level, evac_enabled, rows = [] } = data;
  const [limit, setLimit] = useState(50);

  const setAlert = (level: string) => act('set_alert', { level });
  const setEvac = (enabled: boolean) => act('set_evac', { enabled: enabled ? 1 : 0 });
  const forceState = (id: string, state: string) => act('force_state', { id, state });

  return (
    <Window title="NPC FSM" width={900} height={600} resizable>
      <Window.Content>
        <Stack vertical fill>
          <Stack.Item>
            <Section title="Controls">
              <Stack align="center" justify="space-between">
                <Stack.Item>
                  <LabeledList>
                    <LabeledList.Item label="Alert Level">
                      <Dropdown
                        width={14}
                        selected={alert_level ?? 'none'}
                        options={[
                          ['none', 'None'],
                          ['green', 'Green'],
                          ['blue', 'Blue'],
                          ['red', 'Red'],
                          ['delta', 'Delta'],
                        ]}
                        onSelected={(v) => setAlert(v === 'none' ? '' : (v as string))}
                      />
                      <Button ml={1} icon="times" onClick={() => setAlert('')}>Clear</Button>
                    </LabeledList.Item>
                    <LabeledList.Item label="Evacuation">
                      <Button
                        icon={evac_enabled ? 'check-square' : 'square'}
                        color={evac_enabled ? 'bad' : 'default'}
                        onClick={() => setEvac(!evac_enabled)}
                      >
                        {evac_enabled ? 'Enabled' : 'Disabled'}
                      </Button>
                    </LabeledList.Item>
                  </LabeledList>
                </Stack.Item>
                <Stack.Item>
                  <Stack align="center" gap={1}>
                    <Box>Rows:</Box>
                    <NumberInput width={6} value={limit} minValue={1} maxValue={500} onChange={(v) => setLimit(v)} />
                    <Button icon="sync" onClick={() => act('refresh', { limit })}>
                      Refresh
                    </Button>
                  </Stack>
                </Stack.Item>
              </Stack>
            </Section>
          </Stack.Item>

          <Stack.Item grow>
            <Section fill scrollable title={`NPCs (${rows.length})`}>
              {rows.length === 0 ? (
                <NoticeBox>No NPCs found or no data available.</NoticeBox>
              ) : (
                <Table>
                  <Table.Row header>
                    <Table.Cell>Name</Table.Cell>
                    <Table.Cell>State</Table.Cell>
                    <Table.Cell>Time (s)</Table.Cell>
                    <Table.Cell>EHP</Table.Cell>
                    <Table.Cell>Alarm</Table.Cell>
                    <Table.Cell>Reason</Table.Cell>
                    <Table.Cell>Policy</Table.Cell>
                    <Table.Cell collapsing>Actions</Table.Cell>
                  </Table.Row>
                  {rows.slice(0, limit).map((r) => (
                    <Table.Row key={r.id} selected={false}>
                      <Table.Cell>{r.name}</Table.Cell>
                      <Table.Cell color={STATE_COLORS[r.state] || undefined}>
                        {r.state}
                      </Table.Cell>
                      <Table.Cell>{r.time_in_state_s ?? 0}</Table.Cell>
                      <Table.Cell>{(r.ehp_rounded ?? 0).toFixed(2)}</Table.Cell>
                      <Table.Cell>
                        {r.alarm_nearby ? <Icon name="exclamation-triangle" color="bad" /> : '-'}
                      </Table.Cell>
                      <Table.Cell>
                        {r.last_reason_code || '-'}
                        {r.last_reason_age_s ? ` (${r.last_reason_age_s}s)` : ''}
                      </Table.Cell>
                      <Table.Cell>
                        tick={r.tick_skip ?? 0}, speech={r.speech_radius ?? 0}
                      </Table.Cell>
                      <Table.Cell collapsing>
                        <Stack>
                          <Stack.Item>
                            <Button
                              icon="circle"
                              tooltip="Force Normal"
                              onClick={() => forceState(r.id, 'normal')}
                            />
                          </Stack.Item>
                          <Stack.Item>
                            <Button
                              icon="exclamation"
                              color="average"
                              tooltip="Force Alert"
                              onClick={() => forceState(r.id, 'alert')}
                            />
                          </Stack.Item>
                          <Stack.Item>
                            <Button
                              icon="skull"
                              color="bad"
                              tooltip="Force Critical"
                              onClick={() => forceState(r.id, 'critical')}
                            />
                          </Stack.Item>
                        </Stack>
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

export default NpcAIState;
  // Auto-refresh rows every 1s
  useEffect(() => {
    const h = setInterval(() => {
      act('refresh', { limit });
    }, 1000);
    return () => clearInterval(h);
  }, [limit]);
