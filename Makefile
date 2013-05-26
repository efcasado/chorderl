.PHONY: rel devrel

DEVNODES ?= 1
DEVNODE  ?= dev1
SEQ       = $(shell seq $(DEVNODES))

compile:
	./rebar compile

clean:
	./rebar clean

rel: compile
	./rebar generate

$(eval devrel : $(foreach n,$(SEQ),dev$(n)))

dev%: compile
	rel/gen_dev $@
	./rebar generate target_dir=dev/$@ overlay_vars=../rel/vars/$@_vars.config

start:
	rel/chorderl/bin/chorderl start

devstart:
	rel/dev/$(DEVNODE)/bin/chorderl start

stop:
	rel/chorderl/bin/chorderl stop

devstop:
	rel/dev/$(DEVNODE)/bin/chorderl stop	

attach:
	rel/chorderl/bin/chorderl attach

devattach:
	rel/dev/$(DEVNODE)/bin/chorderl attach
