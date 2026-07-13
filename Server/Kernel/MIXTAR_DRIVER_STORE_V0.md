# Mixtar Driver Store v0

Updated: 05.07.2026

Goal:

```text
Make the Linux RT driver surface explicit in the Mixtar image without exposing
classic Linux distro coldplug policy as the system identity.
```

Native location:

```text
/System/Drivers/Linux/RT/7.1.2/Drivers.config
/System/Drivers/Linux/RT/7.1.2/Drivers.status
/System/Drivers/drivers
```

`Drivers.config` is a SQLite database generated during CoreV05 staging.
`Drivers.status` is the minimal text fallback used by `/System/Drivers/drivers status`.

Runtime split:

```text
/System/Userland  base command set
/System/Drivers   driver store and driver status entrypoint
/System/Tools     future Mixtar administrative tools
```

Policy:

```text
device namespace: /System/Devices
visible /dev:     blocked
visible /etc:     blocked
visible /bin:     blocked
distro coldplug:  blocked for v0
module autoload:  blocked for v0
i915:             blocked in Linux 7.1.2 RT because DRM_I915 depends on !PREEMPT_RT
```

Driver categories:

```text
boot-required
hardware-present
optional-local
blocked
```

This is not a package manager and not a dynamic hardware manager yet. It is the
first explicit Mixtar contract for what the Linux RT kernel is expected to
provide.
