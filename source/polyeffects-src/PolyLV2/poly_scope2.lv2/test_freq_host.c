/* Host-side accuracy test for the frequency detector.

   Drives the real plugin (instantiate / connect_port / activate / run) with
   synthetic signals, reads the frequency the plugin puts in its notify
   packet header, and reports the worst error in cents once settled. Also
   reports how far the integer-sample detector used up to v3f would be off,
   for comparison. Exits non-zero if any case misses its limit.

   Build (host compiler, no cross toolchain needed):
     cc -O2 -o /tmp/test_freq_host test_freq_host.c $(pkg-config --cflags lv2) -lm */
#define _DEFAULT_SOURCE
#include "poly_scope2.c"

#define TEST_RATE 48000.0
#define TEST_BLOCK 128
#define TEST_SETTLE_S 0.6
#define TEST_MEASURE_S 2.0
#define NOTIFY_CAPACITY (1 << 16)

typedef enum { W_SINE, W_SAW_UP, W_SAW_DOWN, W_SQUARE, W_PULSE10, W_TRIANGLE } Wave;
static const char* wave_names[] = {"sine", "saw-up", "saw-down", "square", "pulse10", "triangle"};

/* --- tiny URID map so instantiate() succeeds --- */
static const char* uris[64];
static uint32_t n_uris;
static LV2_URID
map_uri(LV2_URID_Map_Handle h, const char* uri)
{
	(void)h;
	for (uint32_t i = 0; i < n_uris; ++i) {
		if (!strcmp(uris[i], uri)) {
			return i + 1;
		}
	}
	uris[n_uris] = uri;
	return ++n_uris;
}

/* deterministic noise */
static uint32_t rng = 12345u;
static float
noise(void)
{
	rng = rng * 1664525u + 1013904223u;
	return ((float)(rng >> 8) / 16777216.0f) * 2.0f - 1.0f;
}

/* Band-limited-ish waveforms: naive shapes softened with a one-pole low-pass,
   like a real oscillator's finite edges. */
static float
wave_value(Wave w, double phase)
{
	phase -= floor(phase);
	switch (w) {
	case W_SINE: return (float)sin(6.283185307179586 * phase);
	case W_SAW_UP: return (float)(2.0 * phase - 1.0);
	case W_SAW_DOWN: return (float)(1.0 - 2.0 * phase);
	case W_SQUARE: return phase < 0.5 ? 1.0f : -1.0f;
	case W_PULSE10: return phase < 0.1 ? 1.0f : -1.0f;
	case W_TRIANGLE: return (float)(phase < 0.5 ? 4.0 * phase - 1.0 : 3.0 - 4.0 * phase);
	}
	return 0.0f;
}

/* The integer-sample detector as it was up to v3f, for comparison. */
typedef struct {
	uint64_t last;
	float ema;
	bool armed;
} OldDet;
static void
old_push(OldDet* d, float value, uint64_t n)
{
	if (value < -SCOPE_FREQ_HYSTERESIS) {
		d->armed = true;
	} else if (d->armed && value > SCOPE_FREQ_HYSTERESIS) {
		d->armed = false;
		if (d->last > 0) {
			const uint64_t period = n - d->last;
			if (period >= 4) {
				d->ema = d->ema > 0.0f ? d->ema * 0.75f + (float)period * 0.25f : (float)period;
			}
		}
		d->last = n;
	}
}

static double
cents(double measured, double truth)
{
	if (measured <= 0.0) {
		return 1e9;
	}
	return 1200.0 * log2(measured / truth);
}

static double
packet_freq(const uint8_t* buf, uint32_t channel)
{
	const char* hit = memmem(buf, NOTIFY_CAPACITY, "PSCP|3|", 7);
	if (!hit) {
		return -1.0;
	}
	const char* p = strchr(hit + 7, '|');
	if (!p) {
		return -1.0;
	}
	++p;
	for (uint32_t c = 0; c < channel; ++c) {
		p = strchr(p, ',');
		if (!p) {
			return -1.0;
		}
		++p;
	}
	return strtod(p, NULL);
}

typedef struct {
	double max_cents;      /* worst |error| of the new detector */
	double old_max_cents;  /* worst |error| of the v3f detector */
	int packets;
} Result;

static Result
run_case(Wave w, double hz, float amplitude, float dc, float noise_amp, float smooth)
{
	LV2_URID_Map map = {NULL, map_uri};
	LV2_Feature map_feature = {LV2_URID__map, &map};
	const LV2_Feature* features[] = {&map_feature, NULL};
	PolyScope* plugin = (PolyScope*)instantiate(&descriptor, TEST_RATE, "", features);

	float controls[SCOPE_HOLDOFF + 1];
	memset(controls, 0, sizeof(controls));
	controls[SCOPE_TIMEBASE] = 2.0f;
	controls[SCOPE_VOLTS_DIV] = 4.0f;
	controls[SCOPE_TRIGGER_SOURCE] = 1.0f;
	for (int c = 0; c < 4; ++c) {
		controls[SCOPE_VISIBLE_1 + c] = 1.0f;
	}
	float in[4][TEST_BLOCK], out[4][TEST_BLOCK];
	static uint8_t notify_buf[NOTIFY_CAPACITY] __attribute__((aligned(8)));
	for (uint32_t port = 0; port <= SCOPE_HOLDOFF; ++port) {
		if (port >= SCOPE_IN_1 && port <= SCOPE_IN_4) {
			connect_port(plugin, port, in[port - SCOPE_IN_1]);
		} else if (port >= SCOPE_OUT_1 && port <= SCOPE_OUT_4) {
			connect_port(plugin, port, out[port - SCOPE_OUT_1]);
		} else if (port == SCOPE_NOTIFY) {
			connect_port(plugin, port, notify_buf);
		} else {
			connect_port(plugin, port, &controls[port]);
		}
	}
	activate(plugin);

	Result r = {0.0, 0.0, 0};
	OldDet old = {0, 0.0f, false};
	const double phase_step = hz / TEST_RATE;
	double phase = 0.137;
	float lp = 0.0f;
	const uint64_t settle = (uint64_t)(TEST_SETTLE_S * TEST_RATE);
	const uint64_t total = settle + (uint64_t)(TEST_MEASURE_S * TEST_RATE);
	uint64_t n = 0;

	while (n < total) {
		for (int i = 0; i < TEST_BLOCK; ++i) {
			const float raw = wave_value(w, phase) * amplitude;
			lp += (raw - lp) * smooth;
			const float v = lp + dc + noise_amp * noise();
			for (int c = 0; c < 4; ++c) {
				in[c][i] = v;
			}
			phase += phase_step;
			++n;
			old_push(&old, v, n);
		}
		LV2_Atom_Sequence* seq = (LV2_Atom_Sequence*)notify_buf;
		memset(notify_buf, 0, 64);
		seq->atom.size = NOTIFY_CAPACITY - sizeof(LV2_Atom);
		run(plugin, TEST_BLOCK);

		if (n >= settle) {
			const double f = packet_freq(notify_buf, 0);
			if (f > 0.0 || f == 0.0) {
				if (f >= 0.0 && memmem(notify_buf, NOTIFY_CAPACITY, "PSCP|3|", 7)) {
					const double e = fabs(cents(f, hz));
					if (e > r.max_cents) {
						r.max_cents = e;
					}
					r.packets += 1;
					if (old.ema <= 0.0f) {
						r.old_max_cents = 1e9;
					} else {
						const double oe = fabs(cents(TEST_RATE / old.ema, hz));
						if (oe > r.old_max_cents) {
							r.old_max_cents = oe;
						}
					}
				}
			}
		}
	}
	cleanup(plugin);
	return r;
}

/* Time for the reported pitch to settle within 1 cent after a note change. */
static double
note_change_ms(double from_hz, double to_hz)
{
	LV2_URID_Map map = {NULL, map_uri};
	LV2_Feature map_feature = {LV2_URID__map, &map};
	const LV2_Feature* features[] = {&map_feature, NULL};
	PolyScope* plugin = (PolyScope*)instantiate(&descriptor, TEST_RATE, "", features);
	float controls[SCOPE_HOLDOFF + 1];
	memset(controls, 0, sizeof(controls));
	controls[SCOPE_TIMEBASE] = 2.0f;
	float in[4][TEST_BLOCK], out[4][TEST_BLOCK];
	static uint8_t notify_buf[NOTIFY_CAPACITY] __attribute__((aligned(8)));
	for (uint32_t port = 0; port <= SCOPE_HOLDOFF; ++port) {
		if (port >= SCOPE_IN_1 && port <= SCOPE_IN_4) {
			connect_port(plugin, port, in[port - SCOPE_IN_1]);
		} else if (port >= SCOPE_OUT_1 && port <= SCOPE_OUT_4) {
			connect_port(plugin, port, out[port - SCOPE_OUT_1]);
		} else if (port == SCOPE_NOTIFY) {
			connect_port(plugin, port, notify_buf);
		} else {
			connect_port(plugin, port, &controls[port]);
		}
	}
	activate(plugin);
	double phase = 0.0;
	const uint64_t change = (uint64_t)(1.0 * TEST_RATE);
	const uint64_t total = (uint64_t)(2.0 * TEST_RATE);
	double settled_at = -1.0;
	for (uint64_t n = 0; n < total;) {
		const double hz = n < change ? from_hz : to_hz;
		for (int i = 0; i < TEST_BLOCK; ++i, ++n) {
			const float v = (float)sin(6.283185307179586 * phase) * 0.5f;
			for (int c = 0; c < 4; ++c) {
				in[c][i] = v;
			}
			phase += hz / TEST_RATE;
		}
		LV2_Atom_Sequence* seq = (LV2_Atom_Sequence*)notify_buf;
		memset(notify_buf, 0, 64);
		seq->atom.size = NOTIFY_CAPACITY - sizeof(LV2_Atom);
		run(plugin, TEST_BLOCK);
		if (n > change && memmem(notify_buf, NOTIFY_CAPACITY, "PSCP|3|", 7)) {
			const double f = packet_freq(notify_buf, 0);
			const bool ok = fabs(cents(f, to_hz)) < 1.0;
			if (ok && settled_at < 0.0) {
				settled_at = (double)(n - change) * 1000.0 / TEST_RATE;
			} else if (!ok) {
				settled_at = -1.0;
			}
		}
	}
	cleanup(plugin);
	return settled_at;
}

int
main(void)
{
	/* Pitches across the musical range, deliberately not on exact notes. */
	const double pitches[] = {27.6, 41.3, 55.2, 110.4, 220.9, 440.7, 881.5, 1762.0, 3523.0};
	const int n_pitches = (int)(sizeof(pitches) / sizeof(pitches[0]));
	int failures = 0;

	printf("%-9s %-24s %9s %12s %12s\n", "wave", "condition", "Hz", "new (cents)", "v3f (cents)");
	struct {
		const char* label;
		float amp, dc, noise, smooth, limit;
	} conds[] = {
		{"clean 10Vpp", 0.5f, 0.0f, 0.0f, 0.6f, 0.5f},
		{"small 1Vpp", 0.05f, 0.0f, 0.0f, 0.6f, 0.5f},
		{"+2.5V DC offset", 0.25f, 0.25f, 0.0f, 0.6f, 0.5f},
		{"noise -40dB", 0.5f, 0.0f, 0.005f, 0.6f, 1.0f},
	};
	const int n_conds = (int)(sizeof(conds) / sizeof(conds[0]));
	for (int w = 0; w <= W_TRIANGLE; ++w) {
		for (int c = 0; c < n_conds; ++c) {
			for (int p = 0; p < n_pitches; ++p) {
				const Result r = run_case((Wave)w, pitches[p], conds[c].amp, conds[c].dc,
				                          conds[c].noise, conds[c].smooth);
				const bool ok = r.packets > 0 && r.max_cents <= conds[c].limit;
				if (!ok) {
					failures += 1;
				}
				printf("%-9s %-24s %9.1f %12.3f %12.1f %s\n", wave_names[w], conds[c].label,
				       pitches[p], r.max_cents, r.old_max_cents > 1e8 ? -1.0 : r.old_max_cents,
				       ok ? "" : "FAIL");
			}
		}
	}

	const double steps[][2] = {{440.0, 466.16}, {110.0, 220.0}, {880.0, 440.0}, {55.0, 61.74}};
	for (int i = 0; i < 4; ++i) {
		const double ms = note_change_ms(steps[i][0], steps[i][1]);
		const bool ok = ms >= 0.0 && ms <= 200.0;
		if (!ok) {
			failures += 1;
		}
		printf("note change %.2f -> %.2f Hz settles within 1 cent in %.0f ms %s\n",
		       steps[i][0], steps[i][1], ms, ok ? "" : "FAIL");
	}

	printf(failures ? "\nFREQ TESTS FAILED: %d\n" : "\nALL FREQ TESTS PASSED\n", failures);
	return failures ? 1 : 0;
}
