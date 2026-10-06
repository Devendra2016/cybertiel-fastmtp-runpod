# Cyber-Tiel Q6 MTP A/B benchmark

Target:

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf
```

Run on the same A40 pod with the same context and prompt.

## A — MTP OFF

```text
MTP=false
```

## B — MTP ON

```text
MTP=true
MTP_N_MAX=3
```

Record:

```text
prompt tokens
generated tokens
prompt tok/s
generation tok/s
total wall time
VRAM
GPU utilization
task success
```

For agentic evaluation also record:

```text
tool calls
iterations
files changed
tests passed
time-to-success
```

The model card notes that MTP performance depends on the runtime/hardware. Decide using time-to-successful-task-completion, not raw tokens/sec alone.
