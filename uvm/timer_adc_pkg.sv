// ---------------------------------------------------------------------------
// timer_adc_pkg.sv : compact UVM testbench for the Timer + ADC peripheral
//   bus_item -> sequencer -> bus_driver -> DUT
//   DUT -> bus_monitor -> scoreboard (register shadow model)
//   3 tests: reg_test, adc_sw_test, timer_trig_test
// Run with +UVM_TESTNAME=<test>   (xsim: compile/elaborate with -L uvm)
// ---------------------------------------------------------------------------
package timer_adc_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // register addresses
    localparam bit [3:0] R_TMR_CTRL = 4'h0, R_TMR_PRESC = 4'h1, R_TMR_LOAD = 4'h2,
                         R_TMR_CMP  = 4'h3, R_TMR_CNT   = 4'h4, R_ADC_CTRL = 4'h5,
                         R_ADC_SMP  = 4'h6, R_ADC_DIV   = 4'h7, R_THR_LO   = 4'h8,
                         R_THR_HI   = 4'h9, R_ADC_DATA  = 4'hA, R_ADC_RCH   = 4'hB,
                         R_ADC_STAT = 4'hC, R_IRQ_EN    = 4'hD, R_IRQ_STAT  = 4'hE,
                         R_ID       = 4'hF;

    localparam real VREF = 3.3;
    localparam real LSB  = VREF / 256.0;

    // ------------------------------------------------------------ item
    class bus_item extends uvm_sequence_item;
        bit       we;
        bit [3:0] addr;
        bit [7:0] data;     // write data
        bit [7:0] rdata;    // read data (filled by driver / monitor)
        `uvm_object_utils(bus_item)
        function new(string name = "bus_item");
            super.new(name);
        endfunction
        function string convert2string();
            return $sformatf("%s addr=0x%0h data=0x%02h rdata=0x%02h",
                             we ? "WR" : "RD", addr, data, rdata);
        endfunction
    endclass

    // ------------------------------------------------------------ driver
    class bus_driver extends uvm_driver #(bus_item);
        `uvm_component_utils(bus_driver)
        virtual timer_adc_if vif;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual timer_adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set for driver")
        endfunction
        task run_phase(uvm_phase phase);
            vif.cs = 0; vif.we = 0; vif.addr = 0; vif.wdata = 0;
            wait (vif.rst_n === 1'b1);
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask
        // one access = cs high for exactly one clock edge
        task drive(bus_item it);
            @(posedge vif.clk); #1;
            vif.cs = 1; vif.we = it.we; vif.addr = it.addr; vif.wdata = it.data;
            @(posedge vif.clk);          // DUT samples here, rdata is combinational
            it.rdata = vif.rdata;        // value seen by the DUT at this edge
            #1;
            vif.cs = 0; vif.we = 0;
        endtask
    endclass

    // ------------------------------------------------------------ monitor
    class bus_monitor extends uvm_monitor;
        `uvm_component_utils(bus_monitor)
        virtual timer_adc_if vif;
        uvm_analysis_port #(bus_item) ap;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db#(virtual timer_adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set for monitor")
        endfunction
        task run_phase(uvm_phase phase);
            bus_item it;
            wait (vif.rst_n === 1'b1);
            forever begin
                @(posedge vif.clk);
                if (vif.cs === 1'b1) begin
                    it = bus_item::type_id::create("mon_it");
                    it.we = vif.we; it.addr = vif.addr;
                    it.data = vif.wdata; it.rdata = vif.rdata;
                    ap.write(it);
                end
            end
        endtask
    endclass

    // ------------------------------------------------------------ agent
    class bus_agent extends uvm_agent;
        `uvm_component_utils(bus_agent)
        uvm_sequencer #(bus_item) sqr;
        bus_driver  drv;
        bus_monitor mon;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sqr = uvm_sequencer#(bus_item)::type_id::create("sqr", this);
            drv = bus_driver ::type_id::create("drv", this);
            mon = bus_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ------------------------------------------------------------ scoreboard
    // shadow model of the plain read/write registers; checks every read
    class scoreboard extends uvm_subscriber #(bus_item);
        `uvm_component_utils(scoreboard)
        bit [7:0] shadow [16];
        bit       known  [16];
        int       n_checks, n_errors;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            foreach (known[i]) known[i] = 0;
            set_reset(R_TMR_PRESC, 8'h00); set_reset(R_TMR_LOAD, 8'hFF);
            set_reset(R_TMR_CMP,   8'h80); set_reset(R_ADC_CTRL, 8'h00);
            set_reset(R_ADC_SMP,   8'h04); set_reset(R_ADC_DIV,  8'h00);
            set_reset(R_THR_LO,    8'h00); set_reset(R_THR_HI,   8'hFF);
            set_reset(R_IRQ_EN,    8'h00); set_reset(R_ID,       8'hA8);
        endfunction
        function void set_reset(bit [3:0] a, bit [7:0] v);
            shadow[a] = v; known[a] = 1;
        endfunction
        function void write(bus_item t);
            if (t.we) begin
                case (t.addr)
                    R_TMR_PRESC, R_TMR_LOAD, R_TMR_CMP, R_ADC_SMP, R_ADC_DIV,
                    R_THR_LO, R_THR_HI, R_IRQ_EN: begin
                        shadow[t.addr] = t.data; known[t.addr] = 1;
                    end
                    R_ADC_CTRL: begin               // START reads back as 0, bits 7:6 unused
                        shadow[t.addr] = t.data & 8'h3D; known[t.addr] = 1;
                    end
                    default: ;
                endcase
            end else if (known[t.addr]) begin
                n_checks++;
                if (t.rdata !== shadow[t.addr]) begin
                    n_errors++;
                    `uvm_error("SB", $sformatf("read of reg 0x%0h returned 0x%02h, expected 0x%02h",
                                               t.addr, t.rdata, shadow[t.addr]))
                end
            end
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("SB", $sformatf("register checks: %0d, errors: %0d", n_checks, n_errors), UVM_LOW)
        endfunction
    endclass

    // ------------------------------------------------------------ env
    class env extends uvm_env;
        `uvm_component_utils(env)
        bus_agent  agt;
        scoreboard sb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = bus_agent ::type_id::create("agt", this);
            sb  = scoreboard::type_id::create("sb",  this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(sb.analysis_export);
        endfunction
    endclass

    // ------------------------------------------------------------ sequences
    class base_seq extends uvm_sequence #(bus_item);
        `uvm_object_utils(base_seq)
        virtual timer_adc_if vif;
        int n_err = 0;
        function new(string name = "base_seq");
            super.new(name);
        endfunction

        task get_vif();
            if (!uvm_config_db#(virtual timer_adc_if)::get(m_sequencer, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set for sequence")
        endtask
        task wr(bit [3:0] a, bit [7:0] d);
            bus_item it = bus_item::type_id::create("wr_it");
            start_item(it);
            it.we = 1; it.addr = a; it.data = d;
            finish_item(it);
        endtask
        task rd(bit [3:0] a, output bit [7:0] d);
            bus_item it = bus_item::type_id::create("rd_it");
            start_item(it);
            it.we = 0; it.addr = a; it.data = 0;
            finish_item(it);
            d = it.rdata;
        endtask
        task wait_clks(int n);
            repeat (n) @(posedge vif.clk);
        endtask
        task expect_eq(string what, int got, int exp, int tol = 0);
            int diff = (got > exp) ? got - exp : exp - got;
            if (diff > tol) begin
                n_err++;
                `uvm_error("CHK", $sformatf("%s: got %0d, expected %0d", what, got, exp))
            end else
                `uvm_info("CHK", $sformatf("%s: %0d (expected %0d) OK", what, got, exp), UVM_MEDIUM)
        endtask
        function int code_of(real v);
            int c = int'($floor(v / LSB));
            if (c > 255) c = 255;
            if (c < 0)   c = 0;
            return c;
        endfunction
    endclass

    // ---- 1. registers: reset values, write/read-back, ID
    class reg_seq extends base_seq;
        `uvm_object_utils(reg_seq)
        function new(string name = "reg_seq"); super.new(name); endfunction
        task body();
            bit [3:0] rw_regs [8] = '{R_TMR_PRESC, R_TMR_LOAD, R_TMR_CMP, R_ADC_SMP,
                                      R_ADC_DIV, R_THR_LO, R_THR_HI, R_IRQ_EN};
            bit [7:0] pat [2] = '{8'h5A, 8'hA5};
            bit [7:0] d;
            get_vif();
            // reset values (scoreboard checks them as well)
            rd(R_TMR_LOAD, d); expect_eq("reset TMR_LOAD", d, 8'hFF);
            rd(R_TMR_CMP,  d); expect_eq("reset TMR_CMP",  d, 8'h80);
            rd(R_ADC_SMP,  d); expect_eq("reset ADC_SMP",  d, 8'h04);
            rd(R_THR_HI,   d); expect_eq("reset THR_HI",   d, 8'hFF);
            rd(R_ADC_STAT, d); expect_eq("reset ADC_STAT", d, 8'h10);
            rd(R_ID,       d); expect_eq("ID",             d, 8'hA8);
            // write / read-back
            foreach (rw_regs[i]) foreach (pat[j]) begin
                wr(rw_regs[i], pat[j]);
                rd(rw_regs[i], d);
                expect_eq($sformatf("readback reg 0x%0h", rw_regs[i]), d, pat[j]);
            end
            wr(R_ADC_CTRL, 8'h35); rd(R_ADC_CTRL, d); expect_eq("ADC_CTRL readback", d, 8'h35);
            wr(R_ADC_CTRL, 8'h00);
        endtask
    endclass

    // ---- 2. software started conversions on all channels
    class adc_sw_seq extends base_seq;
        `uvm_object_utils(adc_sw_seq)
        function new(string name = "adc_sw_seq"); super.new(name); endfunction
        task body();
            real volts [6] = '{0.0, 0.5, 1.111, 1.66, 3.2, 3.299};
            bit [7:0] d, st, rch;
            int tries;
            get_vif();
            wr(R_ADC_SMP, 8'd2);
            wr(R_ADC_DIV, 8'd0);
            foreach (volts[i]) for (int c = 0; c < 4; c++) begin
                vif.vin[c] = volts[i];
                wr(R_ADC_CTRL, 8'h03 | (c << 4));      // EN + START, software trigger
                tries = 0;
                do begin rd(R_ADC_STAT, st); tries++; end
                while (st[4] && tries < 200);          // wait until FIFO not empty
                if (st[4]) begin
                    n_err++; `uvm_error("CHK", "timeout waiting for ADC result")
                end
                rd(R_ADC_RCH,  rch);
                rd(R_ADC_DATA, d);                     // pops the FIFO
                expect_eq($sformatf("ADC ch%0d @%0.3fV", c, volts[i]), d, code_of(volts[i]), 1);
                expect_eq("RCH.VALID", rch[7], 1);
                expect_eq("RCH.CH",    rch[1:0], c);
                rd(R_ADC_STAT, st);
                expect_eq("FIFO empty after pop", st[4], 1);
            end
            wr(R_ADC_CTRL, 8'h00);
        endtask
    endclass

    // ---- 3. timer triggered conversions, flags, irq, FIFO
    class timer_trig_seq extends base_seq;
        `uvm_object_utils(timer_trig_seq)
        function new(string name = "timer_trig_seq"); super.new(name); endfunction
        task body();
            bit [7:0] d, st;
            int n_pop = 0;
            get_vif();
            vif.vin[1] = 2.0;
            wr(R_TMR_PRESC, 8'd0);
            wr(R_TMR_LOAD,  8'd19);                    // period 20 clocks
            wr(R_TMR_CMP,   8'd5);
            wr(R_ADC_SMP,   8'd1);
            wr(R_ADC_DIV,   8'd0);
            wr(R_IRQ_EN,    8'h03);                    // TMR_OVF | TMR_CMP
            wr(R_ADC_CTRL,  8'h15);                    // EN, trigger = timer ovf, ch1
            wr(R_TMR_CTRL,  8'h01);                    // timer on
            wait_clks(110);
            rd(R_IRQ_STAT, d);
            if (d[1:0] != 2'b11) begin
                n_err++; `uvm_error("CHK", $sformatf("IRQ_STAT 0x%02h: TMR_OVF/TMR_CMP not both set", d))
            end
            if (vif.irq !== 1'b1) begin
                n_err++; `uvm_error("CHK", "irq pin is not high")
            end
            rd(R_TMR_CNT, d);
            if (d > 19) begin
                n_err++; `uvm_error("CHK", $sformatf("TMR_CNT 0x%02h above TMR_LOAD", d))
            end
            rd(R_ADC_STAT, st);
            if (st[3:0] < 3) begin
                n_err++; `uvm_error("CHK", $sformatf("FIFO level %0d, expected >= 3", st[3:0]))
            end
            wr(R_TMR_CTRL, 8'h00);                     // stop timer
            wait_clks(40);                             // let a running conversion finish
            wr(R_IRQ_STAT, 8'h3F);                     // clear all flags
            rd(R_IRQ_STAT, d);
            expect_eq("IRQ_STAT after W1C", d, 0);
            if (vif.irq !== 1'b0) begin
                n_err++; `uvm_error("CHK", "irq pin still high after clear")
            end
            // drain the FIFO, every result must be the code of 2.0 V
            rd(R_ADC_STAT, st);
            while (!st[4] && n_pop < 16) begin
                rd(R_ADC_DATA, d);
                expect_eq($sformatf("FIFO result %0d", n_pop), d, code_of(2.0), 1);
                n_pop++;
                rd(R_ADC_STAT, st);
            end
            if (n_pop < 3) begin
                n_err++; `uvm_error("CHK", "too few results popped")
            end
            wr(R_ADC_CTRL, 8'h00);
        endtask
    endclass

    // ------------------------------------------------------------ tests
    class base_test extends uvm_test;
        `uvm_component_utils(base_test)
        env e;
        function new(string name = "base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            e = env::type_id::create("e", this);
        endfunction
        virtual function base_seq make_seq();
            return base_seq::type_id::create("seq");
        endfunction
        task run_phase(uvm_phase phase);
            base_seq s = make_seq();
            phase.raise_objection(this);
            s.start(e.agt.sqr);
            #200;
            phase.drop_objection(this);
        endtask
        function void report_phase(uvm_phase phase);
            uvm_report_server srv = uvm_report_server::get_server();
            if (srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL) == 0)
                `uvm_info("RESULT", "*** TEST PASSED ***", UVM_NONE)
            else
                `uvm_info("RESULT", "*** TEST FAILED ***", UVM_NONE)
        endfunction
    endclass

    class reg_test extends base_test;
        `uvm_component_utils(reg_test)
        function new(string name = "reg_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        function base_seq make_seq();
            reg_seq s = reg_seq::type_id::create("seq");
            return s;
        endfunction
    endclass

    class adc_sw_test extends base_test;
        `uvm_component_utils(adc_sw_test)
        function new(string name = "adc_sw_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        function base_seq make_seq();
            adc_sw_seq s = adc_sw_seq::type_id::create("seq");
            return s;
        endfunction
    endclass

    class timer_trig_test extends base_test;
        `uvm_component_utils(timer_trig_test)
        function new(string name = "timer_trig_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        function base_seq make_seq();
            timer_trig_seq s = timer_trig_seq::type_id::create("seq");
            return s;
        endfunction
    endclass
endpackage
