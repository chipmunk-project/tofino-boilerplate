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
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}

header ipv4_t ipv4;


field_list ipv4_field_list {
    ipv4.version;
    ipv4.ihl;
    ipv4.diffserv;
    ipv4.totalLen;
    ipv4.identification;
    ipv4.flags;
    ipv4.fragOffset;
    ipv4.ttl;
    ipv4.protocol;
    ipv4.srcAddr;
    ipv4.dstAddr;
}

field_list_calculation ipv4_chksum_calc {
    input {
        ipv4_field_list;
    }
    algorithm : csum16;
    output_width: 16;
}

calculated_field ipv4.hdrChecksum {
    update ipv4_chksum_calc;
}

header_type udp_t { // 8 bytes
    fields {
        srcPort : 16;
        dstPort : 16;
        hdr_length : 16;
        checksum : 16;
    }
}

header udp_t udp;


header_type metadata_t {
    fields {
        // Fill in Metadata with declarations
        condition : 32;
        value1 : 32;
        value2 : 32;
        result1 : 32;
        result2 : 32;
        index : 32;
        salu_flow : 8;
    }
}

metadata metadata_t mdata;

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
    set_metadata(mdata.condition, 1); // This is used for executing a control flow.
    set_metadata(mdata.index, 0);
    return ingress;
}

/** Registers ***/
#define MAX_SIZE 10
// Each register (Stateful ALU) can have many blackbox execution units.
// However, all blackbox units that operate on a SALU must be placed on the same stage.
// In most of my programs, I use two blackbox per SALU (one to update and other to read)
register salu1 {
    width : 32;
    instance_count : MAX_SIZE;
}

//  if (condition) {
//         salu1++;
//         result2 = 1;
//     } else {
//         salu = 0;
//         result2 = 0;
//     }
// }
blackbox stateful_alu salu1_exec1 {
    reg : salu1;
    condition_lo : mdata.condition == 1;
    update_lo_1_predicate : condition_lo;
    update_lo_1_value : register_lo + 1;
    update_lo_1_predicate : not condition_lo;
    update_lo_1_value : 0;
    update_hi_1_predicate : condition_lo;
    update_hi_1_value : 1;
    update_hi_1_predicate : not condition_lo;
    update_hi_2_value : 0;
    output_value : alu_hi;
    output_dst : mdata.result2;
}

// result2 = salu1
blackbox stateful_alu salu1_exec2 {
    reg : salu1;
    output_value : register_lo;
    output_dst : mdata.result2;
}

action action_0x0_1 () {
    modify_field(mdata.result1, mdata.value1);
}

action action_0x0_2 () {
    add(mdata.result1, mdata.value1, mdata.value2);

}

action action_0x1_1 () {
    salu1_exec1.execute_stateful_alu(mdata.index);
}

action action_0x1_2 () {
    salu1_exec2.execute_stateful_alu(mdata.index);
}

action nop () {
    // Do nothing
}
// A table can optionally read some metadata, and execute an action of the listed ones.
// In case, there is no other conditions, mdata.condition should be set to 1
table table_0x0 {
    reads {
        mdata.condition : exact; // This is to be filled by the compiler.
        // Can be one or more of such PHV contents
    }
    actions {
        action_0x0_1; // action1
        action_0x0_2; // action2
        nop;
    }
    default_action: nop;
}

table table_0x1 {
    reads {
        mdata.condition : exact; // This is to be filled by the compiler.
        // Can be one or more of such PHV contents
    }
    actions {
        action_0x1_1; // action1 for SALU
        nop;
    }
    default_action: nop;
}

table table_0x2 {
    reads {
        mdata.condition : exact; // This is to be filled by the compiler.
        // Can be one or more of such PHV contents
    }
    actions {
        action_0x1_2; // action2 for SALU
        nop;
    }
    default_action: nop;
}


control ingress {
    // Stage 0
    apply(table_0x0); // Stateless ALU
    if (mdata.salu_flow == 1) {
        apply(table_0x1); // Stateful  ALU
    } else {
        apply(table_0x2); // Stateful  ALU
    }
    // Stage 1
    // To be similar to Stage 0
}

control egress {

}
