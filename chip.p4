/*
 * Chipmunk P4 Tofino Reference (This program passes the Tofino compiler. Haven't fed test packets yet.)
 * TODO: Need to add an input/output test harness. Input could be packet generator, output could be switch CPU port.
 */
#include <tofino/intrinsic_metadata.p4>    // Parser metadata, ingress pipeline (where to queue, ingree port), egress pipeline (queue depth), etc.
#include <tofino/constants.p4>             // Copied from previous uses of stateful ALU.
#include "tofino/stateful_alu_blackbox.p4" // Stateful ALU blackbox definitions
#include "tofino/lpf_blackbox.p4"          // Low-pass filter blackbox definitions (can be deleted)


/* Declare Header */                       // Standard Ethernet Header
header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header ethernet_t ethernet;

header_type ipv4_t {                   // Standard IPv4 header
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

field_list_calculation ipv4_chksum_calc {            // Calculate checksum of IPv4 everytime we forward a packet.
    input {
        ipv4_field_list;
    }
    algorithm : csum16;
    output_width: 16;
}

calculated_field ipv4.hdrChecksum {
    update ipv4_chksum_calc;
}

header_type udp_t { // 8 bytes                       // UDP header; Can also add TCP header if required later on. For now, we can only process UDP packets.
    fields {
        srcPort : 16;
        dstPort : 16;
        hdr_length : 16;
        checksum : 16;
    }
}

header udp_t udp;


header_type metadata_t {
  // Placeholder for all the stateless variables (variable definitions, results, etc.)
  // These get loaded into the PHV. Lifetime is through the ingress and egress pipeline.
  // Values are the inputs to the stateless ALUs.
  // Results are the outputs to the stateless ALUs.
  // We are putting the outputs and inputs of both stateless+stateful ALUs in metadata.
  // We can also do this in header (header and metadata are almost synonymous.)
    fields {
        // Fill in Metadata with declarations
        condition : 32;  // condition is a placeholder for condition for executing stateful and stateless ALU
        value1 : 32;     // placeholder for inputs to stateless/stateful ALUs.
        value2 : 32;     // Not restricted to reading from value1 and writing to result1
        value3 : 32;     // All fields, whether in metadata or packet headers can be read/written to in the same uniform manner.
        value4 : 32;
        result1 : 32;    // placeholder for outputs to stateless/stateful ALUs.
        result2 : 32;
        result3 : 32;
        result4 : 32;    // Can increase the number of values and results as desired. 4 results (2 stateful + 2 stateless ALUs).
        index : 32;      // placeholder for array address of stateful ALU array (P4 register).
        salu_flow : 8;   // can be ignored. Was used for control flow before.
    }
}

metadata metadata_t mdata; // declaration for metadata.

/* Declare Parser */
parser start { // keyword to start parsing
	return select(current(96,16)){ // start from offset of 96 bits and retrieve 16 bytes to get Ethernet header.
		0x0800: parse_ethernet;
	}
}

parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        /** Fill Whatever ***/
        0x0800     : parse_ipv4;       // IPv4 ethertype
        default: ingress;
    }
}
parser parse_ipv4 {
    extract(ipv4);
    set_metadata(mdata.condition, 1); // This is used for executing a control flow.
    set_metadata(mdata.index, 0);     // Set metadata in the parser before it hits ingress pipeline.
    // Can use set_metadata in parser to create test inputs by calling set_metadata on the index and values.
    // Can use this as a test input generator by using set_metadata with random values.
    // Still need the packet generator to actually generate the packets themselves.
    // Placeholder for adding UDP and TCP parsers as well.
    return ingress;
}

/** Registers (stateful variables) ***/
#define MAX_SIZE 10
// MAX SIZE is the maximum size of the array. For each stateful ALU, we can define the size of the stateful ALU.
// MAX_SIZE of up to 100K is allowed. Limited by the size of the SRAM in a single stage.

// Each register (Stateful ALU) can have many blackbox execution units.
// However, all blackbox units that operate on a SALU must be placed on the same stage.
// In most of my programs, I use two blackbox per SALU (one to update and other to read)
// register corresponds to state group in the Chipmunk world.
register salu1 {
    width : 32; // 32 bit integers. Really 2 slices of 32 bits each.
    instance_count : MAX_SIZE; // Can get up to 100 K pairs of 32 bit integers per stage.
    // The P4 compiler will complain if it runs out of SRAM.
}
// In a single match-action table, you can't have two actions in the same table that manipulate the same register.
// Might affect the code that we generate, but doesn't seem to affect what the hardware can do itself.
// Restriction: A P4 register can only be manipulated by one table per packet (no races).

// Below is pseudocode for lines 159 through 171.
//  if (condition) {
//         salu1++;
//         result2 = 1;
//     } else {
//         salu = 0;
//         result2 = 0;
//     }
// }
// Note: Pravein wrote a .alu spec for this stateful ALU in the Google DOc.
blackbox stateful_alu salu1_exec1 {
    reg : salu1;  // placeholder for which register/stateful variable
    condition_lo : mdata.condition == 1; // 2 conditions: lo is the lower slice and hi is the higher slice.
    condition_hi : mdata.condition == 1;
    // Condition placeholder: {register|metadata} {==|<|>|>=|!=} {immediate operand}.
    // metadata compared to metadata is not allowed.
    // Simple conditions can be encoded right here. Complicated conditions can be moved to previous stateless ALUs.
    update_lo_1_predicate : condition_lo; // Predicate format: {condition_lo|!condition_lo|condition_high|!condition_high}
                                          // 166 is equivalent to line 150
                                          // Usually had to either use condition_lo or condition_high, not both.
    update_lo_1_value : register_lo + 1;  // salu1++
    update_lo_2_predicate : not condition_lo; // Predicate format: {condition_lo|!condition_lo|condition_high|!condition_high}
                                              // 
    update_lo_2_value : 0;                // salu = 0
    update_hi_1_predicate : condition_hi; // similarly for condition hi
    update_hi_1_value : 1;
    update_hi_2_predicate : not condition_hi;
    update_hi_2_value : 0;
    output_value : alu_hi;                // Can only output of one of the two 32-bit slices. We choose to get alu hi here.
    output_dst : mdata.result2;           // Stored in result 2 as the output.
}

// result2 = salu1
blackbox stateful_alu salu1_exec2 {
    reg : salu1;
    output_value : register_lo;
    output_dst : mdata.result2;
}

register salu2 {
    width : 32;
    instance_count : MAX_SIZE;
}

// Can define as many blackboxes per stateful ALU and state variable.
// Only one of them can execute per packet.
// NG's question: Can update_lo_1_predicate and update_lo_2_predicate be arbitrary?
// Or does one HAVE to be the negation of the other?
// Pravein thinks it has to be negation.
// IN general: probe the Tofino compiler to find out.
//  if (condition) {
//         salu1++;
//         result3 = 1;
//     } else {
//         salu = 0;
//         result3 = 0;
//     }
// }
blackbox stateful_alu salu2_exec1 {
    reg : salu2;
    condition_lo : mdata.condition == 1;
    condition_hi : mdata.condition == 1;
    update_lo_1_predicate : condition_lo;
    update_lo_1_value : register_lo + 1;
    update_lo_1_predicate : not condition_lo;
    update_lo_1_value : 0;
    update_hi_1_predicate : condition_hi;
    update_hi_1_value : 1;
    update_hi_1_predicate : not condition_hi;
    update_hi_2_value : 0;
    output_value : alu_hi;
    output_dst : mdata.result3;
}

// result2 = salu1
// Output operation from stateful ALU.
// Hasn't been used anywhere.
// register_lo is the original value of the register.
// alu_lo (updated value).
blackbox stateful_alu salu2_exec2 {
    reg : salu2;
    output_value : register_lo;
    output_dst : mdata.result3;
}

// Write into a PHV container or packet field
action action_0x0_1 () {
    modify_field(mdata.result1, mdata.value1);
}

// Addition
action action_0x0_2 () {
    add(mdata.result1, mdata.value1, mdata.value2);
}

// Subtraction
action action_0x0_3 () {
    subtract(mdata.result1, mdata.value1, mdata.value2);
}

// Bit and
action action_0x0_4 () {
    //result1 = value1 & value2
    bit_and(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_5 () {
    //result1 = ~value1 & value2
    bit_andca(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_6 () {
    //result1 = value1 & ~value2
    bit_andcb(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_7 () {
    //result1 = ~(value1 & value2)
    bit_nand(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_8 () {
    //result1 = ~(value1 | value2)
    bit_nor(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_9 () {
    //result1 = ~value1
    bit_not(mdata.result1, mdata.value1);
}

action action_0x0_10 () {
    //result1 = value1 | value2
    bit_or(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_11 () {
    //result1 = ~value1 | value2
    bit_orca(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_12 () {
    //result1 = value1 | ~value2
    bit_orcb(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_13 () {
    //result1 = ~(value1 ^ value2)
    bit_xnor(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_14 () {
    //result1 = value1 ^ value2
    bit_xor(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_15 () {
    //result1 = max(value1, value2)
    max(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_16 () {
    //result1 = min(value1, value2)
    min(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_17 () {
    //result1 = value1 - value2
    subtract(mdata.result1, mdata.value1, mdata.value2);
}

action action_0x0_18 () {
    //result1 -= value1
    subtract_from_field(mdata.result1, mdata.value1);
}

action action_0x0_19 () {
    //result1 = value1 << value2(immediate value)
    shift_left(mdata.result1, mdata.value1, 1);
}

action action_0x0_20 () { // action
    //result1 = value1 >> value2(immediate value)
    shift_right(mdata.result1, mdata.value1, 1); // primitive action
}

action action_0x0_21 () {
    // value1,value2 = value2,value1
    swap(mdata.value1, mdata.value2);
}
// 21 such stateless ALU operations.
// Can't add any more primitive operations.
// In a single action, only a single stateful ALU can be accessed.

// Action 0x3 for table 0x3
action action_0x3_1 () {
    //result4 =value1
    modify_field(mdata.result4, mdata.value3);
}

action action_0x3_2 () {
    //result4 = value1 + value2
    add(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_3 () {
    //result4 +=value1
    add_to_field(mdata.result4, mdata.value3);
}

action action_0x3_4 () {
    //result4 = value1 & value2
    bit_and(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_5 () {
    //result4 = ~value1 & value2
    bit_andca(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_6 () {
    //result4 = value1 & ~value2
    bit_andcb(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_7 () {
    //result4 = ~(value1 & value2)
    bit_nand(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_8 () {
    //result4 = ~(value1 | value2)
    bit_nor(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_9 () {
    //result4 = ~value1
    bit_not(mdata.result4, mdata.value3);
}

action action_0x3_10 () {
    //result4 = value1 | value2
    bit_or(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_11 () {
    //result4 = ~value1 | value2
    bit_orca(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_12 () {
    //result4 = value1 | ~value2
    bit_orcb(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_13 () {
    //result4 = ~(value1 ^ value2)
    bit_xnor(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_14 () {
    //result4 = value1 ^ value2
    bit_xor(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_15 () {
    //result4 = max(value1, value2)
    max(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_16 () {
    //result4 = min(value1, value2)
    min(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_17 () {
    //result4 = value1 - value2
    subtract(mdata.result4, mdata.value3, mdata.value4);
}

action action_0x3_18 () {
    //result4 -= value1
    subtract_from_field(mdata.result4, mdata.value3);
}

action action_0x3_19 () {
    //result4 = value1 << value2(immediate value)
    shift_left(mdata.result4, mdata.value3, 1);
}

action action_0x3_20 () {
    //result4 = value1 >> value2(immediate value)
    shift_right(mdata.result4, mdata.value3, 1);
}

action action_0x3_21 () {
    // value1,value2 = value2,value1
    swap(mdata.value3, mdata.value4);
}

// The above is a copy of the 21 stateless ALU actions.

// Stateful ALU Action
action action_0x1_1 () {
    salu1_exec1.execute_stateful_alu(mdata.index);
}


action action_0x2_1 () {
    salu2_exec1.execute_stateful_alu(mdata.index);
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
        action_0x0_1; // action1 - assignment
        action_0x0_2; // action2 - add
        action_0x0_3; // action3 - subtract
        action_0x0_4;
        action_0x0_5;
        action_0x0_6;
        action_0x0_7;
        action_0x0_8;
        action_0x0_9;
        action_0x0_10;
        action_0x0_11;
        action_0x0_12;
        action_0x0_13;
        action_0x0_14;
        action_0x0_15;
        action_0x0_16;
        action_0x0_17;
        action_0x0_18;
        action_0x0_19;
        action_0x0_20;
        // action_0x0_21; // Swap has a problem now. TBFixed
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
        action_0x2_1; // action2 for SALU
        nop;
    }
    default_action: nop;
}

table table_0x3 {
    reads {
        mdata.condition : exact; // This is to be filled by the compiler.
        // Can be one or more of such PHV contents
    }
    actions {
        action_0x3_1; // action1 - assignment
        action_0x3_2; // action2 - add
        action_0x3_3; // action3 - subtract
        action_0x3_4;
        action_0x3_5;
        action_0x3_6;
        action_0x3_7;
        action_0x3_8;
        action_0x3_9;
        action_0x3_10;
        action_0x3_11;
        action_0x3_12;
        action_0x3_13;
        action_0x3_14;
        action_0x3_15;
        action_0x3_16;
        action_0x3_17;
        action_0x3_18;
        action_0x3_19;
        action_0x3_20;
        //action_0x3_21; // Swap has a problem now. TBFixed
        nop;
    }
    default_action: nop;
}
control ingress {
    // Stage 0
    // 2 x 1 - 2 Stateless & 2 Stateful ALU, 1 Stage
    apply(table_0x0); // Stateless ALU
    apply(table_0x1); // Stateful  ALU
    apply(table_0x2); // Stateful  ALU
    apply(table_0x3); // Stateless ALU
    // Stage 1
    // To be similar to Stage 0
}

control egress {

}
