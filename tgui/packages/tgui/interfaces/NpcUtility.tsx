import { useState, useMemo } from 'react';
import {
  Box,
  Button,
  Dropdown,
  Icon,
  Input,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Stack,
  Table,
} from 'tgui-core/components';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type TopItem = { id: string; score: number };
type Row = {
  id: string;
  name: string;
  fsm_state: string;
  current_goal: string;
  goal_age_s: number;
  top: TopItem[];
  forced_active: boolean;
  forced_goal: string;
  can_emerg_interrupt: boolean;
  forced_warning: string;
  utility_eval_ms: number;
  utility_uptime_s: number;
  evals: number;
  switches: number;
  preempts: number;
};

type Data = {
  config: Record<string, unknown>;
  rows: Row[];
};

const asPairs = (cfg: Record<string, unknown>) =>
  Object.entries(cfg || {}).map(([k, v]) => [k, String(v)] as [string, string]);

export const NpcUtility = () => {
  const { data, act } = useBackend<Data>();
  const { config = {}, rows = [] } = data;
  const [limit, setLimit] = useState(50);
  const [cfgKey, setCfgKey] = useState<string>('npc_utility_enabled');
  const [cfgVal, setCfgVal] = useState<string>('1');
  const cfgOptions = useMemo(() => asPairs(config).map(([k]) => [k, k] as [string, string]), [config]);

  const setConfig = () => act('set_config', { key: cfgKey, value: cfgVal });
  const forceGoal = (id: string, goal: string) => act('force_goal', { id, goal });
  const reeval = (id?: string) => act('re_eval', { id: id ?? '' });

  return (
    <Window title="NPC Utility" width={1000} height={700} resizable>
      <Window.Content>
        <Stack vertical fill>
          <Stack.Item>
            <Section title="Controls">
              <Stack align="center" justify="space-between">
                <Stack.Item>
                  <LabeledList>
                    <LabeledList.Item label="Config Key">
                      <Dropdown width={28} selected={cfgKey} options={cfgOptions} onSelected={(v) => setCfgKey(v as string)} />
                    </LabeledList.Item>
                    <LabeledList.Item label="Value">
                      <Input width={28} value={cfgVal} onChange={(v) => setCfgVal(v)} />
                      <Button ml={1} icon="save" onClick={setConfig}>
                        Set
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
                    <Button icon="redo" onClick={() => reeval()}>
                      Re-eval All
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
                    <Table.Cell>FSM</Table.Cell>
                    <Table.Cell>Goal</Table.Cell>
                    <Table.Cell>Age (s)</Table.Cell>
                    <Table.Cell>Top</Table.Cell>
                    <Table.Cell>Forced</Table.Cell>
                    <Table.Cell>Perf</Table.Cell>
                    <Table.Cell>Counters</Table.Cell>
                    <Table.Cell collapsing>Actions</Table.Cell>
                  </Table.Row>
                  {rows.slice(0, limit).map((r) => (
                    <Table.Row key={r.id} selected={false}>
                      <Table.Cell>{r.name}</Table.Cell>
                      <Table.Cell>{r.fsm_state || '-'}</Table.Cell>
                      <Table.Cell>
                        {r.current_goal || '-'}
                        {r.forced_active ? (
                          <Box mt={0.5} color={r.can_emerg_interrupt ? 'average' : 'good'}>
                            <Icon mr={0.5} name="exclamation-circle" /> Forced: {r.forced_goal || '?'}
                            {r.forced_warning ? ` (${r.forced_warning})` : ''}
                          </Box>
                        ) : null}
                      </Table.Cell>
                      <Table.Cell>{r.goal_age_s ?? 0}</Table.Cell>
                      <Table.Cell>
                        {(r.top || []).map((t, i) => (
                          <Box key={i}>{t.id}: {(t.score ?? 0).toFixed(2)}</Box>
                        ))}
                      </Table.Cell>
                      <Table.Cell>{r.forced_active ? 'Yes' : 'No'}</Table.Cell>
                    <Table.Cell>{(r.utility_eval_ms ?? 0).toFixed(0)} ms</Table.Cell>
                      <Table.Cell>
                        {(() => {
                          const evals = r.evals ?? 0;
                          const up = Math.max(1, r.utility_uptime_s ?? 0);
                          const ePerHour = Math.round((evals / up) * 3600);
                          return (
                            <>
                              E/h:{ePerHour} S:{r.switches ?? 0} P:{r.preempts ?? 0}
                            </>
                          );
                        })()}
                      </Table.Cell>
                      <Table.Cell collapsing>
                        <Stack>
                          <Stack.Item>
                            <Button.Input
                              fluid
                              icon="flag"
                              placeholder="Force goal id"
                              onCommit={(goal) => forceGoal(r.id, goal)}
                            />
                          </Stack.Item>
                          <Stack.Item>
                            <Button icon="redo" onClick={() => reeval(r.id)}>
                              Re-eval
                            </Button>
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

export default NpcUtility;
