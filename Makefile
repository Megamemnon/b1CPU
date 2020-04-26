SYN = yosys
PNR = nextpnr-ice40
GEN = icepack
PROG = iceprog
TERM = screen
PORT = /dev/ttyUSB1
BAUD = 9600

TOP = b1.v
PCF = hx8k.pcf
PNR_FLAGS = --hx8k

OUTPUT = $(patsubst %.v,%.bin,$(TOP))

all: $(OUTPUT)

%.bin: %.asc
	$(GEN) $< $@

%.asc: %.json
	$(PNR) $(PNR_FLAGS) --pcf $(PCF) --json $< --asc $@

%.json: %.v
	$(SYN) -p "read_verilog $<; synth_ice40 -flatten -json $@"

clean:
	rm -f *.asc *.bin *.json

flash: $(OUTPUT)
	$(PROG) $<
	@echo "To end the serial terminal session, press Ctrl+a followed by k."
	@sleep 1s
	$(TERM) $(PORT) $(BAUD)

.PHONY: all clean flash
