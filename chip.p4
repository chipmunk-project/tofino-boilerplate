/*
 * Chipmunk P4 Tofino Reference
 */
#include <tofino/intrinsic_metadata.p4>
#include <tofino/constants.p4>
#include "tofino/stateful_alu_blackbox.p4"
#include "tofino/lpf_blackbox.p4"


/* Declare Header */
header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header ethernet_t ethernet;

header_type ipv4_t {
    fields { // Variable: can use these fields for output from packet processing program.
             // Note: this is just for ease of prototyping. In practice, we would use a separate header for this.
        field1 : 32;
        field2 : 32;
        field3 : 32; 
        field4 : 32;
        field5 : 32;
    }
}

header ipv4_t ipv4;

/* Declare Parser */
parser start {
	return select(current(96,16)){
		0x0800: parse_ethernet;
	}
}

parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        /** Fill Whatever ***/
        0x0800     : parse_ipv4;
        default: ingress;
    }
}
parser parse_ipv4 {
    extract(ipv4);
    return ingress;
}

/** Registers ***/
#define MAX_SIZE 10
register salu1 {
    width : 32;
    instance_count : MAX_SIZE; // TODO: Figure out what MAX_SIZE should be.
}

blackbox stateful_alu salu1_exec1 {
    reg : salu1; // Variable, but can associate a stateful ALU blackbox with only one state variable (register)
    condition_lo : 1 == 1; // Variable, condition for triggerring ALU_LO1 (needs to be a predicate)
    condition_hi : 1 == 1; // Variable, predicate
    update_lo_1_predicate : condition_lo; // Variable, predicate TODO: figure out how this relates to conditon_lo 
    update_lo_1_value : register_lo + 7;  // Variable, arithmetic expression
    update_lo_2_predicate : not condition_lo; // Variable predicate
    update_lo_2_value : 0; // Variable arithmetic expression
    update_hi_1_predicate : condition_hi; // Variable predicate
    update_hi_1_value : 1; // Variable arithmetic expression
    update_hi_2_predicate : not condition_hi; // Variable predicate
    update_hi_2_value : 0; // Variable arithmetic expression
    output_value : alu_lo; // Variable: either alu_lo or register_lo or alu_hi or register_hi
    output_dst : ipv4.field5; // Variable: any PHV container or packet field
    initial_register_lo_value : 3; // Variable: any number
    initial_register_hi_value : 10; // Variable: any number
}

// Variable: Repeat SALUs as many times as needed to create an M-by-N grid.

// Stateful ALU Action
action action_0x1_1 () {
    salu1_exec1.execute_stateful_alu(0);
}

// Stateless ALU action
action action_assign() {
    modify_field(ipv4.field1, 0xDEADFA11);
    modify_field(ipv4.field2, 0xFACEFEED); 
    modify_field(ipv4.field3, 0xDEADFEED);
    modify_field(ipv4.field4, 0xCAFED00D);
}

// Stateless ALU table
table table_0x0 {
    actions {
        action_assign;
    }
    default_action: action_assign;
}

// Stateful ALU table
table table_0x1 {
    actions {
        action_0x1_1; // action1 for SALU
    }
    default_action: action_0x1_1;
}

// Variable: Create as many tables as required depending on the grid size.

action set_egr(egress_spec) {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, egress_spec);
}

table mac_forward {
    reads {
        ethernet.dstAddr : exact;
    }
    actions {
        set_egr;
    }
    size:20;
}

control ingress {
    // Stage 0
    // 2 x 1 - 2 Stateless & 2 Stateful ALU, 1 Stage
    apply(table_0x0); // Stateless ALU
    apply(table_0x1); // Stateful  ALU
    // Call as many tables as required depending on the grid size.
    // Sequence tables in different stages if needed depending on dependencies.
    // TODO: Figure out from Pravein how to place one table in one stage and another in a different stage.

    // Stage 1
    // To be similar to Stage 0
    // Mac Forwarding by default
    apply(mac_forward);
}

control egress {

}
