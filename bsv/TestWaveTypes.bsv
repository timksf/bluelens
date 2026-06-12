package TestWaveTypes;

import StmtFSM :: *;
import Vector :: *;

import TestHelper :: *;

typedef enum {
    ModeIdle,
    ModeRead,
    ModeWrite,
    ModeFault,
    ModeRecover
} Mode_t deriving(Bits, Eq, FShow);

typedef enum {
    KindControl,
    KindData,
    KindStatus
} Kind_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(4) seq_num;
    Bool accepted;
    Mode_t mode;
} Header_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(8) low;
    Bit#(8) high;
    Kind_t kind;
} WordPair_t deriving(Bits, Eq, FShow);

typedef union tagged {
    void Empty;
    Bit#(8) Byte;
    WordPair_t Pair;
    Header_t Header;
} Payload_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(12) address;
    Bit#(8) data;
    Bool last;
} WriteCommand_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(12) address;
    Bit#(4) count;
    Mode_t mode;
} ReadCommand_t deriving(Bits, Eq, FShow);

typedef struct {
    Kind_t kind;
    Bit#(10) code;
    Header_t header_snapshot;
} ReportCommand_t deriving(Bits, Eq, FShow);

typedef union tagged {
    void NoCommand;
    WriteCommand_t WriteCommand;
    ReadCommand_t ReadCommand;
    ReportCommand_t ReportCommand;
} Command_t deriving(Bits, Eq, FShow);

typedef struct {
    Header_t header;
    Payload_t payload;
    Maybe#(Bit#(7)) optional;
    Vector#(3, Bit#(5)) lanes;
    Tuple2#(Mode_t, Bit#(6)) summary;
    Bool ready;
} Packet_t deriving(Bits, Eq, FShow);

function Header_t makeHeader(Bit#(4) seq_num, Bool accepted, Mode_t mode);
    return Header_t {
        seq_num: seq_num,
        accepted: accepted,
        mode: mode
    };
endfunction

function WordPair_t makePair(Bit#(8) low, Bit#(8) high, Kind_t kind);
    return WordPair_t {
        low: low,
        high: high,
        kind: kind
    };
endfunction

function WriteCommand_t makeWriteCommand(
    Bit#(12) address,
    Bit#(8) data,
    Bool last
);
    return WriteCommand_t {
        address: address,
        data: data,
        last: last
    };
endfunction

function ReadCommand_t makeReadCommand(
    Bit#(12) address,
    Bit#(4) count,
    Mode_t mode
);
    return ReadCommand_t {
        address: address,
        count: count,
        mode: mode
    };
endfunction

function ReportCommand_t makeReportCommand(
    Kind_t kind,
    Bit#(10) code,
    Header_t header_snapshot
);
    return ReportCommand_t {
        kind: kind,
        code: code,
        header_snapshot: header_snapshot
    };
endfunction

function Vector#(3, Bit#(5)) makeLanes(
    Bit#(5) lane0,
    Bit#(5) lane1,
    Bit#(5) lane2
);
    Vector#(3, Bit#(5)) lanes = newVector;
    lanes[0] = lane0;
    lanes[1] = lane1;
    lanes[2] = lane2;
    return lanes;
endfunction

function Packet_t makePacket(
    Header_t header,
    Payload_t payload,
    Maybe#(Bit#(7)) optional,
    Vector#(3, Bit#(5)) lanes,
    Tuple2#(Mode_t, Bit#(6)) summary,
    Bool ready
);
    return Packet_t {
        header: header,
        payload: payload,
        optional: optional,
        lanes: lanes,
        summary: summary,
        ready: ready
    };
endfunction

(* synthesize *)
module [Module] mkTestWaveTypes(TestHelper::TestHandler);

    Header_t header0 = makeHeader(0, False, ModeIdle);
    WordPair_t pair0 = makePair(0, 0, KindControl);

    Reg#(Mode_t) rg_mode <- mkReg(ModeIdle);
    Reg#(Kind_t) rg_kind <- mkReg(KindControl);
    Reg#(Header_t) rg_header <- mkReg(header0);
    Reg#(WordPair_t) rg_pair <- mkReg(pair0);
    Reg#(Payload_t) rg_payload <- mkReg(tagged Empty);
    Reg#(Command_t) rg_command <- mkReg(tagged NoCommand);
    Reg#(Maybe#(Bit#(7))) rg_optional <- mkReg(tagged Invalid);
    Reg#(Vector#(3, Bit#(5))) rg_lanes <- mkReg(replicate(0));
    Reg#(Tuple2#(Mode_t, Bit#(6))) rg_summary <-
        mkReg(tuple2(ModeIdle, 0));
    Reg#(Packet_t) rg_packet <- mkReg(makePacket(
        header0,
        tagged Empty,
        tagged Invalid,
        replicate(0),
        tuple2(ModeIdle, 0),
        False
    ));

    Stmt s = seq
        delay(2);
        action
            Header_t header = makeHeader(1, True, ModeRead);
            WordPair_t pair = makePair(8'h12, 8'h34, KindData);
            Vector#(3, Bit#(5)) lanes = makeLanes(1, 2, 3);

            rg_mode <= ModeRead;
            rg_kind <= KindData;
            rg_header <= header;
            rg_pair <= pair;
            rg_payload <= tagged Byte 8'hA5;
            rg_command <= tagged WriteCommand makeWriteCommand(
                12'h123,
                8'hA5,
                False
            );
            rg_optional <= tagged Valid 7'h55;
            rg_lanes <= lanes;
            rg_summary <= tuple2(ModeRead, 6'h11);
            rg_packet <= makePacket(
                header,
                tagged Byte 8'hA5,
                tagged Valid 7'h55,
                lanes,
                tuple2(ModeRead, 6'h11),
                True
            );
        endaction
        delay(3);
        action
            Header_t header = makeHeader(7, False, ModeWrite);
            WordPair_t pair = makePair(8'hDE, 8'hAD, KindStatus);
            Vector#(3, Bit#(5)) lanes = makeLanes(5'h1F, 5'h10, 5'h08);

            rg_mode <= ModeWrite;
            rg_kind <= KindStatus;
            rg_header <= header;
            rg_pair <= pair;
            rg_payload <= tagged Pair pair;
            rg_command <= tagged ReadCommand makeReadCommand(
                12'hABC,
                4'h7,
                ModeWrite
            );
            rg_optional <= tagged Invalid;
            rg_lanes <= lanes;
            rg_summary <= tuple2(ModeWrite, 6'h22);
            rg_packet <= makePacket(
                header,
                tagged Pair pair,
                tagged Invalid,
                lanes,
                tuple2(ModeWrite, 6'h22),
                False
            );
        endaction
        delay(3);
        action
            Header_t header = makeHeader(4'hC, True, ModeFault);
            Vector#(3, Bit#(5)) lanes = makeLanes(5'h03, 5'h0C, 5'h1B);

            rg_mode <= ModeFault;
            rg_kind <= KindControl;
            rg_header <= header;
            rg_payload <= tagged Header header;
            rg_command <= tagged ReportCommand makeReportCommand(
                KindStatus,
                10'h2D5,
                header
            );
            rg_optional <= tagged Valid 7'h7F;
            rg_lanes <= lanes;
            rg_summary <= tuple2(ModeFault, 6'h3F);
            rg_packet <= makePacket(
                header,
                tagged Header header,
                tagged Valid 7'h7F,
                lanes,
                tuple2(ModeFault, 6'h3F),
                True
            );
        endaction
        delay(3);
        action
            Header_t header = makeHeader(0, False, ModeRecover);

            rg_mode <= ModeRecover;
            rg_header <= header;
            rg_pair <= makePair(8'hBE, 8'hEF, KindControl);
            rg_payload <= tagged Empty;
            rg_command <= tagged NoCommand;
            rg_optional <= tagged Valid 7'h01;
            rg_lanes <= replicate(0);
            rg_summary <= tuple2(ModeRecover, 6'h01);
            rg_packet <= makePacket(
                header,
                tagged Empty,
                tagged Valid 7'h01,
                replicate(0),
                tuple2(ModeRecover, 6'h01),
                False
            );
        endaction
        delay(2);
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

endpackage
