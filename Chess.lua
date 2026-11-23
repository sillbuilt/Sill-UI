--!native
--!optimize 2
--[[
    SILL X | SOLO 2800+ UNIVERSAL AUTO BOT (ZERO-FREEZE WATCHDOG EDITION)
    - แก้บั๊กเล่นๆ อยู่แล้วบอทหยุดเดินกลางเกม 100%:
        1. ล็อกพิกัดตาราง State.board[1..64] เป็นมาตรฐานเดียวกับเซิร์ฟเวอร์ (ตัด detectTopDownBoard ที่เคยพลิกกลับด้านกระดานผิดตอนหมากบุกเข้าแดนศัตรูกลางเกม)
        2. ปลดล็อกขีดจำกัด retryCount < 4 (ที่เดิมถ้าเน็ตกระตุกหรือติดอนิเมชันครบ 4 ครั้ง บอทจะหยุดเดินถาวร)
        3. เพิ่มระบบ Tiered Recovery Watchdog: หากยิงตาเดินหลักไปแล้วเซิร์ฟเวอร์ยังไม่ขยับภายใน 2 ครั้ง ครั้งถัดไปจะสลับใช้ตาเดินสำรอง (Alt Move / BuiltIn Validator) อัตโนมัติทันที!
        4. รีเฟรชตัวชี้กระดานใน GC ทุก 1 วินาที เพื่อไม่ให้ค้างที่กระดานเก่าตอนกด Rematch เริ่มเกมใหม่
]]

local __SOLO_2800_PAYLOAD = [===[
--!native
--!optimize 2
local ENV = (type(getgenv) == "function" and getgenv()) or _G

if type(ENV.__SillSoloCleanup) == "function" then
	pcall(ENV.__SillSoloCleanup)
end
if type(ENV.SillChessBotCleanup) == "function" then
	pcall(ENV.SillChessBotCleanup)
end

local AUTORUN_FILE = "SillChessBot_AutoExec.lua"
local LOADER_FILE  = "SillChessBot_AutoLoader.lua"
local STATE_FILE   = "SillChessBot_State.json"

local bit32 = bit32
local band, bor, bxor, lshift, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift

--==============================================================================
-- 1. STOCKFISH-STYLE BOARD, DYNAMIC ROW-ORDER DETECTOR & INCREMENTAL PeSTO EVAL
--==============================================================================
local WHITE = 0
local BLACK = 8

local EMPTY  = 0
local PAWN   = 1
local KNIGHT = 2
local BISHOP = 3
local ROOK   = 4
local QUEEN  = 5
local KING   = 6

local CR_WK = 1
local CR_WQ = 2
local CR_BK = 4
local CR_BQ = 8

local FLAG_NORMAL  = 0
local FLAG_CAPTURE = 1
local FLAG_EP      = 2
local FLAG_CASTLE  = 4
local FLAG_PROMO   = 8

local KNIGHT_DELTAS = { -33, -31, -18, -14, 14, 18, 31, 33 }
local BISHOP_DELTAS = { -17, -15, 15, 17 }
local ROOK_DELTAS   = { -16, -1, 1, 16 }
local QUEEN_DELTAS  = { -17, -16, -15, -1, 1, 15, 16, 17 }

local CASTLE_MASK = {}
for i = 0, 127 do CASTLE_MASK[i] = 15 end
CASTLE_MASK[0]   = 15 - CR_WQ
CASTLE_MASK[4]   = 15 - (CR_WK + CR_WQ)
CASTLE_MASK[7]   = 15 - CR_WK
CASTLE_MASK[112] = 15 - CR_BQ
CASTLE_MASK[116] = 15 - (CR_BK + CR_BQ)
CASTLE_MASK[119] = 15 - CR_BK

local MG_VALUE  = { [0] = 0, [PAWN] = 82, [KNIGHT] = 337, [BISHOP] = 365, [ROOK] = 477, [QUEEN] = 1025, [KING] = 20000 }
local EG_VALUE  = { [0] = 0, [PAWN] = 94, [KNIGHT] = 281, [BISHOP] = 297, [ROOK] = 512, [QUEEN] = 936,  [KING] = 20000 }
local SEE_VALUE = { [0] = 0, [PAWN] = 100, [KNIGHT] = 320, [BISHOP] = 330, [ROOK] = 500, [QUEEN] = 950, [KING] = 20000 }
local PHASE_INC = { [0] = 0, [PAWN] = 0, [KNIGHT] = 1, [BISHOP] = 1, [ROOK] = 2, [QUEEN] = 4, [KING] = 0 }

local MG_PAWN = {
	  0,   0,   0,   0,   0,   0,   0,   0,
	 98, 134,  61,  95,  68, 126,  34, -11,
	 -6,   7,  26,  31,  65,  56,  25, -20,
	-14,  13,   6,  21,  23,  12,  17, -23,
	-27,  -2,  -5,  12,  17,   6,  10, -25,
	-26,  -4,  -4, -10,   3,   3,  33, -12,
	-35,  -1, -20, -23, -15,  24,  38, -22,
	  0,   0,   0,   0,   0,   0,   0,   0,
}
local EG_PAWN = {
	  0,   0,   0,   0,   0,   0,   0,   0,
	178, 173, 158, 134, 147, 132, 165, 187,
	 94, 100,  85,  67,  56,  53,  82,  84,
	 32,  24,  13,   5,  -2,   4,  17,  17,
	 13,   9,  -3,  -7,  -7,  -8,   3,  -1,
	  4,   7,  -6,   1,   0,  -5,  -1,  -8,
	 13,   8,   8,  10,  13,   0,   2,  -7,
	  0,   0,   0,   0,   0,   0,   0,   0,
}
local MG_KNIGHT = {
	-167, -89, -34, -49,  61, -97, -15, -107,
	 -73, -41,  72,  36,  23,  62,   7,  -17,
	 -47,  60,  37,  65,  84, 129,  73,   44,
	  -9,  17,  19,  53,  37,  69,  18,   22,
	 -13,   4,  16,  13,  28,  19,  21,   -8,
	 -23,  -9,  12,  10,  19,  17,  25,  -16,
	 -29, -53, -12,  -3,  -1,  18, -14,  -19,
	-105, -21, -58, -33, -17, -28, -19,  -23,
}
local EG_KNIGHT = {
	-58, -38, -13, -28, -31, -27, -63, -99,
	-25,  -8, -25,  -2,  -9, -25, -24, -52,
	-24, -20,  10,   9,  -1,  -9, -19, -41,
	-17,   3,  22,  22,  22,  11,   8, -18,
	-18,  -6,  16,  25,  16,  17,   4, -18,
	-23,  -3,  -1,  15,  10,  -3, -20, -22,
	-42, -20, -10,  -5,  -2, -20, -23, -44,
	-29, -51, -23, -15, -22, -18, -50, -64,
}
local MG_BISHOP = {
	-29,   4, -82, -37, -25, -42,   7,  -8,
	-26,  16, -18, -13,  30,  59,  18, -47,
	-16,  37,  43,  40,  35,  50,  37,  -2,
	 -4,   5,  19,  50,  37,  37,   7,  -2,
	 -6,  13,  13,  26,  34,  12,  10,   4,
	  0,  15,  15,  15,  14,  27,  18,  10,
	  4,  15,  16,   0,   7,  21,  33,   1,
	-33,  -3, -14, -21, -13, -12, -39, -21,
}
local EG_BISHOP = {
	-14, -21, -11,  -8,  -7,  -9, -17, -24,
	 -8,  -4,   7, -12,  -3, -13,  -4, -14,
	  2,  -8,   0,  -1,  -2,   6,   0,   4,
	 -3,   9,  12,   9,  14,  10,   3,   2,
	 -6,   3,  13,  19,   7,  10,  -3,  -9,
	-12,  -3,   8,  10,  13,   3,  -7, -15,
	-14, -18,  -7,  -1,   4,  -9, -15, -27,
	-23,  -9, -23,  -5,  -9, -16,  -5, -17,
}
local MG_ROOK = {
	 32,  42,  32,  51,  63,   9,  31,  43,
	 27,  32,  58,  62,  80,  67,  26,  44,
	 -5,  19,  26,  36,  17,  45,  61,  16,
	-24, -11,   7,  26,  24,  35,  -8, -20,
	-36, -26, -12,  -1,   9,  -7,   6, -23,
	-45, -25, -16, -17,   3,   0,  -5, -33,
	-44, -16, -20,  -9,  -1,  11,  -6, -71,
	-19, -13,   1,  17,  16,   7, -37, -26,
}
local EG_ROOK = {
	 13,  10,  18,  15,  12,  12,   8,   5,
	 11,  13,  13,  11,  -3,   3,   8,   3,
	  7,   7,   7,   5,   4,  -3,  -5,  -3,
	  4,   3,  13,   1,   2,   1,  -1,   2,
	  3,   5,   8,   4,  -5,  -6,  -8, -11,
	 -4,   0,  -5,  -1,  -7, -12,  -8, -16,
	 -6,  -6,   0,   2,  -9,  -9, -11,  -3,
	 -9,   2,   3,  -1,  -5, -13,   4, -20,
}
local MG_QUEEN = {
	-28,   0,  29,  12,  59,  44,  43,  45,
	-24, -39,  -5,   1, -16,  57,  28,  54,
	-13, -17,   7,   8,  29,  56,  47,  57,
	-27, -27, -16, -16,  -1,  17,  -2,   1,
	 -9, -26,  -9, -10,  -2,  -4,   3,  -3,
	-14,   2, -11,  -2,  -5,   2,  14,   5,
	-35,  -8,  11,   2,   8,  15,  -3,   1,
	 -1, -18,  -9,  10, -15, -25, -31, -50,
}
local EG_QUEEN = {
	 -9,  22,  22,  27,  27,  19,  10,  20,
	-17,  20,  32,  41,  58,  25,  30,   0,
	-20,   6,   9,  49,  47,  35,  19,   9,
	  3,  22,  24,  45,  57,  40,  57,  36,
	-18,  28,  19,  47,  31,  34,  39,  23,
	-16, -27,  15,   6,   9,  17,  10,   5,
	-22, -23, -30, -16, -16, -23, -36, -32,
	-33, -28, -22, -43,  -5, -32, -20, -41,
}
local MG_KING = {
	-65,  23,  16, -15, -56, -34,   2,  13,
	 29,  -1, -20,  -7,  -8,  -4, -38, -29,
	 -9,  24,   2, -16, -20,   6,  22, -22,
	-17, -20, -12, -27, -30, -25, -14, -36,
	-49,  -1, -27, -39, -46, -44, -33, -51,
	-14, -14, -22, -46, -44, -30, -15, -27,
	  1,   7,  -8, -64, -43, -16,   9,   8,
	-15,  36,  12, -54,   8, -28,  24,  14,
}
local EG_KING = {
	-74, -35, -18, -18, -11,  15,   4, -17,
	-12,  17,  14,  17,  17,  38,  23,  11,
	 10,  17,  23,  15,  20,  45,  44,  13,
	 -8,  22,  24,  27,  26,  33,  26,   3,
	-18,  -4,  21,  24,  27,  23,   9, -11,
	-19,  -3,  11,  21,  23,  16,   7,  -9,
	-27, -11,   4,  13,  14,   4,  -5, -17,
	-53, -34, -21, -11, -28, -14, -24, -43,
}

local MG_PST_RAW = { [PAWN] = MG_PAWN, [KNIGHT] = MG_KNIGHT, [BISHOP] = MG_BISHOP, [ROOK] = MG_ROOK, [QUEEN] = MG_QUEEN, [KING] = MG_KING }
local EG_PST_RAW = { [PAWN] = EG_PAWN, [KNIGHT] = EG_KNIGHT, [BISHOP] = EG_BISHOP, [ROOK] = EG_ROOK, [QUEEN] = EG_QUEEN, [KING] = EG_KING }

local MG_SIGNED = {}
local EG_SIGNED = {}

do
	for color = 0, 8, 8 do
		local sign = (color == WHITE) and 1 or -1
		for pType = 1, 6 do
			local code = color + pType
			MG_SIGNED[code] = table.create(128, 0)
			EG_SIGNED[code] = table.create(128, 0)
			local mgMat = (pType == KING) and 0 or MG_VALUE[pType]
			local egMat = (pType == KING) and 0 or EG_VALUE[pType]
			local mgRaw = MG_PST_RAW[pType]
			local egRaw = EG_PST_RAW[pType]

			for r = 0, 7 do
				for f = 0, 7 do
					local sq0x88 = lshift(r, 4) + f
					local tblRank = (color == WHITE) and (7 - r) or r
					local idx64 = tblRank * 8 + f + 1
					MG_SIGNED[code][sq0x88] = sign * (mgMat + mgRaw[idx64])
					EG_SIGNED[code][sq0x88] = sign * (egMat + egRaw[idx64])
				end
			end
		end
	end
end

local ZOBRIST_PIECE_LO, ZOBRIST_PIECE_HI   = {}, {}
local ZOBRIST_CASTLE_LO, ZOBRIST_CASTLE_HI = {}, {}
local ZOBRIST_EP_LO, ZOBRIST_EP_HI         = {}, {}
local ZOBRIST_SIDE_LO, ZOBRIST_SIDE_HI     = 0, 0

do
	local seed = 1070372
	local function rand32()
		seed = bxor(seed, lshift(seed, 13))
		seed = bxor(seed, rshift(seed, 17))
		seed = bxor(seed, lshift(seed, 5))
		return band(seed, 0xFFFFFFFF)
	end
	for p = 1, 14 do
		ZOBRIST_PIECE_LO[p], ZOBRIST_PIECE_HI[p] = {}, {}
		for sq = 0, 127 do
			ZOBRIST_PIECE_LO[p][sq] = rand32()
			ZOBRIST_PIECE_HI[p][sq] = rand32()
		end
	end
	for c = 0, 15 do
		ZOBRIST_CASTLE_LO[c] = rand32()
		ZOBRIST_CASTLE_HI[c] = rand32()
	end
	for sq = 0, 127 do
		ZOBRIST_EP_LO[sq] = rand32()
		ZOBRIST_EP_HI[sq] = rand32()
	end
	ZOBRIST_SIDE_LO = rand32()
	ZOBRIST_SIDE_HI = rand32()
end

local function packMove(from, to, cap, promo, flags)
	return bor(from, lshift(to, 7), lshift(cap, 14), lshift(promo, 18), lshift(flags, 21))
end

local function algebraicToSq(str)
	if not str or #str < 2 then return -1 end
	local file = string.byte(str, 1) - 97
	local rank = tonumber(string.sub(str, 2, 2)) - 1
	if file < 0 or file > 7 or not rank or rank < 0 or rank > 7 then return -1 end
	return lshift(rank, 4) + file
end

local Board = {}
Board.__index = Board

local function newBoard()
	local self = setmetatable({}, Board)
	self.squares  = table.create(128, EMPTY)
	for i = 0, 127 do self.squares[i] = EMPTY end
	self.side     = WHITE
	self.castling = 15
	self.ep       = -1
	self.halfmove = 0
	self.fullmove = 1
	self.kingSq   = { [WHITE] = 4, [BLACK] = 116 }
	self.hashLo   = 0
	self.hashHi   = 0
	self.mg       = 0
	self.eg       = 0
	self.phase    = 0
	self.history  = {}
	self.ply      = 0
	return self
end

function Board:recomputeState()
	local lo, hi = 0, 0
	local mg, eg, ph = 0, 0, 0
	local sqs = self.squares
	for r = 0, 7 do
		local row = lshift(r, 4)
		for f = 0, 7 do
			local sq = row + f
			local p = sqs[sq]
			if p ~= EMPTY then
				lo = bxor(lo, ZOBRIST_PIECE_LO[p][sq])
				hi = bxor(hi, ZOBRIST_PIECE_HI[p][sq])
				mg = mg + MG_SIGNED[p][sq]
				eg = eg + EG_SIGNED[p][sq]
				ph = ph + PHASE_INC[band(p, 7)]
			end
		end
	end
	lo = bxor(lo, ZOBRIST_CASTLE_LO[self.castling])
	hi = bxor(hi, ZOBRIST_CASTLE_HI[self.castling])
	if self.ep ~= -1 then
		lo = bxor(lo, ZOBRIST_EP_LO[self.ep])
		hi = bxor(hi, ZOBRIST_EP_HI[self.ep])
	end
	if self.side == BLACK then
		lo = bxor(lo, ZOBRIST_SIDE_LO)
		hi = bxor(hi, ZOBRIST_SIDE_HI)
	end
	self.hashLo, self.hashHi = lo, hi
	self.mg, self.eg, self.phase = mg, eg, ph
end

function Board:isSquareAttacked(sq, bySide)
	local sqs = self.squares
	if bySide == WHITE then
		if band(sq - 17, 0x88) == 0 and sqs[sq - 17] == (WHITE + PAWN) then return true end
		if band(sq - 15, 0x88) == 0 and sqs[sq - 15] == (WHITE + PAWN) then return true end
	else
		if band(sq + 17, 0x88) == 0 and sqs[sq + 17] == (BLACK + PAWN) then return true end
		if band(sq + 15, 0x88) == 0 and sqs[sq + 15] == (BLACK + PAWN) then return true end
	end

	local targetKnight = bySide + KNIGHT
	for i = 1, 8 do
		local t = sq + KNIGHT_DELTAS[i]
		if band(t, 0x88) == 0 and sqs[t] == targetKnight then return true end
	end

	local targetKing = bySide + KING
	for i = 1, 8 do
		local t = sq + QUEEN_DELTAS[i]
		if band(t, 0x88) == 0 and sqs[t] == targetKing then return true end
	end

	local targetBishop = bySide + BISHOP
	local targetQueen  = bySide + QUEEN
	for i = 1, 4 do
		local d = BISHOP_DELTAS[i]
		local t = sq + d
		while band(t, 0x88) == 0 do
			local p = sqs[t]
			if p ~= EMPTY then
				if p == targetBishop or p == targetQueen then return true end
				break
			end
			t = t + d
		end
	end

	local targetRook = bySide + ROOK
	for i = 1, 4 do
		local d = ROOK_DELTAS[i]
		local t = sq + d
		while band(t, 0x88) == 0 do
			local p = sqs[t]
			if p ~= EMPTY then
				if p == targetRook or p == targetQueen then return true end
				break
			end
			t = t + d
		end
	end
	return false
end

-- Least Valuable Attacker to square `sq` by `bySide` (Used for Stockfish SEE)
function Board:getLeastValuableAttacker(sq, bySide)
	local sqs = self.squares
	if bySide == WHITE then
		if band(sq - 17, 0x88) == 0 and sqs[sq - 17] == (WHITE + PAWN) then return PAWN end
		if band(sq - 15, 0x88) == 0 and sqs[sq - 15] == (WHITE + PAWN) then return PAWN end
	else
		if band(sq + 17, 0x88) == 0 and sqs[sq + 17] == (BLACK + PAWN) then return PAWN end
		if band(sq + 15, 0x88) == 0 and sqs[sq + 15] == (BLACK + PAWN) then return PAWN end
	end

	local targetKnight = bySide + KNIGHT
	for i = 1, 8 do
		local t = sq + KNIGHT_DELTAS[i]
		if band(t, 0x88) == 0 and sqs[t] == targetKnight then return KNIGHT end
	end

	local targetBishop = bySide + BISHOP
	local queenFound = false
	local targetQueen = bySide + QUEEN
	for i = 1, 4 do
		local d = BISHOP_DELTAS[i]
		local t = sq + d
		while band(t, 0x88) == 0 do
			local p = sqs[t]
			if p ~= EMPTY then
				if p == targetBishop then return BISHOP
				elseif p == targetQueen then queenFound = true end
				break
			end
			t = t + d
		end
	end

	local targetRook = bySide + ROOK
	for i = 1, 4 do
		local d = ROOK_DELTAS[i]
		local t = sq + d
		while band(t, 0x88) == 0 do
			local p = sqs[t]
			if p ~= EMPTY then
				if p == targetRook then return ROOK
				elseif p == targetQueen then queenFound = true end
				break
			end
			t = t + d
		end
	end

	if queenFound then return QUEEN end

	local targetKing = bySide + KING
	for i = 1, 8 do
		local t = sq + QUEEN_DELTAS[i]
		if band(t, 0x88) == 0 and sqs[t] == targetKing then return KING end
	end
	return 0
end

function Board:inCheck(side)
	side = side or self.side
	return self:isSquareAttacked(self.kingSq[side], bxor(side, 8))
end

function Board:makeMove(move)
	local sqs  = self.squares
	local side = self.side
	local opp  = bxor(side, 8)

	local from  = band(move, 0x7F)
	local to    = band(rshift(move, 7), 0x7F)
	local cap   = band(rshift(move, 14), 0xF)
	local promo = band(rshift(move, 18), 0x7)
	local flags = band(rshift(move, 21), 0xF)

	local piece = sqs[from]
	if piece == EMPTY or band(piece, 8) ~= side then
		return false
	end
	local pType = band(piece, 7)

	local ply = self.ply + 1
	self.ply = ply
	local hist = self.history[ply]
	if not hist then
		hist = {}
		self.history[ply] = hist
	end
	hist.move     = move
	hist.castling = self.castling
	hist.ep       = self.ep
	hist.halfmove = self.halfmove
	hist.hashLo   = self.hashLo
	hist.hashHi   = self.hashHi
	hist.mg       = self.mg
	hist.eg       = self.eg
	hist.phase    = self.phase

	local lo, hi     = self.hashLo, self.hashHi
	local mg, eg, ph = self.mg, self.eg, self.phase

	if self.ep ~= -1 then
		lo = bxor(lo, ZOBRIST_EP_LO[self.ep])
		hi = bxor(hi, ZOBRIST_EP_HI[self.ep])
		self.ep = -1
	end

	sqs[from] = EMPTY
	lo = bxor(lo, ZOBRIST_PIECE_LO[piece][from])
	hi = bxor(hi, ZOBRIST_PIECE_HI[piece][from])
	mg = mg - MG_SIGNED[piece][from]
	eg = eg - EG_SIGNED[piece][from]

	if band(flags, FLAG_CAPTURE) ~= 0 then
		if band(flags, FLAG_EP) ~= 0 then
			local capSq = (side == WHITE) and (to - 16) or (to + 16)
			sqs[capSq] = EMPTY
			lo = bxor(lo, ZOBRIST_PIECE_LO[cap][capSq])
			hi = bxor(hi, ZOBRIST_PIECE_HI[cap][capSq])
			mg = mg - MG_SIGNED[cap][capSq]
			eg = eg - EG_SIGNED[cap][capSq]
		else
			lo = bxor(lo, ZOBRIST_PIECE_LO[cap][to])
			hi = bxor(hi, ZOBRIST_PIECE_HI[cap][to])
			mg = mg - MG_SIGNED[cap][to]
			eg = eg - EG_SIGNED[cap][to]
			ph = ph - PHASE_INC[band(cap, 7)]
		end
		self.halfmove = 0
	elseif pType == PAWN then
		self.halfmove = 0
		if to - from == 32 or from - to == 32 then
			local epSq = rshift(from + to, 1)
			self.ep = epSq
			lo = bxor(lo, ZOBRIST_EP_LO[epSq])
			hi = bxor(hi, ZOBRIST_EP_HI[epSq])
		end
	else
		self.halfmove = self.halfmove + 1
	end

	local placedPiece = (promo ~= 0) and (side + promo) or piece
	sqs[to] = placedPiece
	lo = bxor(lo, ZOBRIST_PIECE_LO[placedPiece][to])
	hi = bxor(hi, ZOBRIST_PIECE_HI[placedPiece][to])
	mg = mg + MG_SIGNED[placedPiece][to]
	eg = eg + EG_SIGNED[placedPiece][to]
	if promo ~= 0 then
		ph = ph + PHASE_INC[promo]
	end

	if pType == KING then
		self.kingSq[side] = to
		if band(flags, FLAG_CASTLE) ~= 0 then
			local rFrom, rTo
			if to == 6 then rFrom, rTo = 7, 5
			elseif to == 2 then rFrom, rTo = 0, 3
			elseif to == 118 then rFrom, rTo = 119, 117
			elseif to == 114 then rFrom, rTo = 112, 115 end
			local rook = side + ROOK
			sqs[rFrom] = EMPTY
			sqs[rTo]   = rook
			lo = bxor(lo, ZOBRIST_PIECE_LO[rook][rFrom], ZOBRIST_PIECE_LO[rook][rTo])
			hi = bxor(hi, ZOBRIST_PIECE_HI[rook][rFrom], ZOBRIST_PIECE_HI[rook][rTo])
			mg = mg - MG_SIGNED[rook][rFrom] + MG_SIGNED[rook][rTo]
			eg = eg - EG_SIGNED[rook][rFrom] + EG_SIGNED[rook][rTo]
		end
	end

	local newCastle = band(self.castling, CASTLE_MASK[from], CASTLE_MASK[to])
	if newCastle ~= self.castling then
		lo = bxor(lo, ZOBRIST_CASTLE_LO[self.castling], ZOBRIST_CASTLE_LO[newCastle])
		hi = bxor(hi, ZOBRIST_CASTLE_HI[self.castling], ZOBRIST_CASTLE_HI[newCastle])
		self.castling = newCastle
	end

	self.side = opp
	lo = bxor(lo, ZOBRIST_SIDE_LO)
	hi = bxor(hi, ZOBRIST_SIDE_HI)
	self.hashLo, self.hashHi = lo, hi
	self.mg, self.eg, self.phase = mg, eg, ph

	if self:isSquareAttacked(self.kingSq[side], opp) then
		self:unmakeMove()
		return false
	end
	return true
end

function Board:unmakeMove()
	local ply  = self.ply
	local hist = self.history[ply]
	self.ply   = ply - 1

	local move    = hist.move
	self.castling = hist.castling
	self.ep       = hist.ep
	self.halfmove = hist.halfmove
	self.hashLo   = hist.hashLo
	self.hashHi   = hist.hashHi
	self.mg       = hist.mg
	self.eg       = hist.eg
	self.phase    = hist.phase

	local side = bxor(self.side, 8)
	self.side  = side

	local sqs   = self.squares
	local from  = band(move, 0x7F)
	local to    = band(rshift(move, 7), 0x7F)
	local cap   = band(rshift(move, 14), 0xF)
	local promo = band(rshift(move, 18), 0x7)
	local flags = band(rshift(move, 21), 0xF)

	local movedPiece = (promo ~= 0) and (side + PAWN) or sqs[to]
	sqs[from] = movedPiece

	if band(flags, FLAG_EP) ~= 0 then
		sqs[to] = EMPTY
		local capSq = (side == WHITE) and (to - 16) or (to + 16)
		sqs[capSq] = cap
	elseif band(flags, FLAG_CAPTURE) ~= 0 then
		sqs[to] = cap
	else
		sqs[to] = EMPTY
	end

	if band(movedPiece, 7) == KING then
		self.kingSq[side] = from
		if band(flags, FLAG_CASTLE) ~= 0 then
			local rFrom, rTo
			if to == 6 then rFrom, rTo = 7, 5
			elseif to == 2 then rFrom, rTo = 0, 3
			elseif to == 118 then rFrom, rTo = 119, 117
			elseif to == 114 then rFrom, rTo = 112, 115 end
			sqs[rFrom] = side + ROOK
			sqs[rTo]   = EMPTY
		end
	end
end

function Board:generateMoves(capturesOnly)
	local moves = {}
	local n = 0
	local sqs = self.squares
	local side = self.side
	local opp = bxor(side, 8)

	local function addMove(m)
		n = n + 1
		moves[n] = m
	end

	for r = 0, 7 do
		local row = lshift(r, 4)
		for f = 0, 7 do
			local sq = row + f
			local p = sqs[sq]
			if p ~= EMPTY and band(p, 8) == side then
				local pType = band(p, 7)

				if pType == PAWN then
					local dir = (side == WHITE) and 16 or -16
					local startRank = (side == WHITE) and 1 or 6
					local promoRank = (side == WHITE) and 6 or 1
					local capOffsets = (side == WHITE) and { 15, 17 } or { -17, -15 }

					for i = 1, 2 do
						local to = sq + capOffsets[i]
						if band(to, 0x88) == 0 then
							local target = sqs[to]
							if target ~= EMPTY and band(target, 8) == opp then
								if r == promoRank then
									addMove(packMove(sq, to, target, QUEEN, FLAG_CAPTURE + FLAG_PROMO))
									addMove(packMove(sq, to, target, ROOK, FLAG_CAPTURE + FLAG_PROMO))
									addMove(packMove(sq, to, target, BISHOP, FLAG_CAPTURE + FLAG_PROMO))
									addMove(packMove(sq, to, target, KNIGHT, FLAG_CAPTURE + FLAG_PROMO))
								else
									addMove(packMove(sq, to, target, 0, FLAG_CAPTURE))
								end
							elseif to == self.ep then
								addMove(packMove(sq, to, opp + PAWN, 0, FLAG_CAPTURE + FLAG_EP))
							end
						end
					end

					if not capturesOnly then
						local to = sq + dir
						if band(to, 0x88) == 0 and sqs[to] == EMPTY then
							if r == promoRank then
								addMove(packMove(sq, to, 0, QUEEN, FLAG_PROMO))
								addMove(packMove(sq, to, 0, ROOK, FLAG_PROMO))
								addMove(packMove(sq, to, 0, BISHOP, FLAG_PROMO))
								addMove(packMove(sq, to, 0, KNIGHT, FLAG_PROMO))
							else
								addMove(packMove(sq, to, 0, 0, FLAG_NORMAL))
								if r == startRank then
									local to2 = to + dir
									if sqs[to2] == EMPTY then
										addMove(packMove(sq, to2, 0, 0, FLAG_NORMAL))
									end
								end
							end
						end
					end

				elseif pType == KNIGHT or pType == KING then
					local deltas = (pType == KNIGHT) and KNIGHT_DELTAS or QUEEN_DELTAS
					for i = 1, 8 do
						local to = sq + deltas[i]
						if band(to, 0x88) == 0 then
							local target = sqs[to]
							if target == EMPTY then
								if not capturesOnly then
									addMove(packMove(sq, to, 0, 0, FLAG_NORMAL))
								end
							elseif band(target, 8) == opp then
								addMove(packMove(sq, to, target, 0, FLAG_CAPTURE))
							end
						end
					end

					if pType == KING and not capturesOnly then
						local cr = self.castling
						if side == WHITE and sq == 4 then
							if band(cr, CR_WK) ~= 0 and sqs[5] == EMPTY and sqs[6] == EMPTY then
								if not self:isSquareAttacked(4, BLACK) and not self:isSquareAttacked(5, BLACK) and not self:isSquareAttacked(6, BLACK) then
									addMove(packMove(4, 6, 0, 0, FLAG_CASTLE))
								end
							end
							if band(cr, CR_WQ) ~= 0 and sqs[3] == EMPTY and sqs[2] == EMPTY and sqs[1] == EMPTY then
								if not self:isSquareAttacked(4, BLACK) and not self:isSquareAttacked(3, BLACK) and not self:isSquareAttacked(2, BLACK) then
									addMove(packMove(4, 2, 0, 0, FLAG_CASTLE))
								end
							end
						elseif side == BLACK and sq == 116 then
							if band(cr, CR_BK) ~= 0 and sqs[117] == EMPTY and sqs[118] == EMPTY then
								if not self:isSquareAttacked(116, WHITE) and not self:isSquareAttacked(117, WHITE) and not self:isSquareAttacked(118, WHITE) then
									addMove(packMove(116, 118, 0, 0, FLAG_CASTLE))
								end
							end
							if band(cr, CR_BQ) ~= 0 and sqs[115] == EMPTY and sqs[114] == EMPTY and sqs[113] == EMPTY then
								if not self:isSquareAttacked(116, WHITE) and not self:isSquareAttacked(115, WHITE) and not self:isSquareAttacked(114, WHITE) then
									addMove(packMove(116, 114, 0, 0, FLAG_CASTLE))
								end
							end
						end
					end

				else
					local deltas = (pType == BISHOP) and BISHOP_DELTAS or ((pType == ROOK) and ROOK_DELTAS or QUEEN_DELTAS)
					local numDirs = #deltas
					for i = 1, numDirs do
						local d = deltas[i]
						local to = sq + d
						while band(to, 0x88) == 0 do
							local target = sqs[to]
							if target == EMPTY then
								if not capturesOnly then
									addMove(packMove(sq, to, 0, 0, FLAG_NORMAL))
								end
							else
								if band(target, 8) == opp then
									addMove(packMove(sq, to, target, 0, FLAG_CAPTURE))
								end
								break
							end
							to = to + d
						end
					end
				end
			end
		end
	end

	return moves, n
end

--==============================================================================
-- 2. POSITIONAL EVALUATOR (Incremental PeSTO + Mobility/Outposts/Rooks/King)
--==============================================================================
local PASSED_BONUS_EG = { [0] = 0, 14, 28, 52, 86, 135, 190, 0 }
local wPawnCount   = table.create(8, 0)
local bPawnCount   = table.create(8, 0)
local wPawnMaxRank = table.create(8, -1)
local bPawnMinRank = table.create(8, 8)
local wRookSquares = table.create(4, 0)
local bRookSquares = table.create(4, 0)

local function evaluate(board)
	local sqs = board.squares
	local mgDiff = board.mg
	local egDiff = board.eg
	local gamePhase = board.phase
	if gamePhase > 24 then gamePhase = 24 end

	local wBishops, bBishops = 0, 0
	local wRooks, bRooks = 0, 0

	for f = 0, 7 do
		wPawnCount[f]   = 0
		bPawnCount[f]   = 0
		wPawnMaxRank[f] = -1
		bPawnMinRank[f] = 8
	end

	for r = 0, 7 do
		local row = lshift(r, 4)
		for f = 0, 7 do
			local sq = row + f
			local p = sqs[sq]
			if p ~= EMPTY then
				local pType = band(p, 7)
				if band(p, 8) == WHITE then
					if pType == PAWN then
						wPawnCount[f] = wPawnCount[f] + 1
						if r > wPawnMaxRank[f] then wPawnMaxRank[f] = r end
						-- Pawn Phalanx / Defended Pawn bonus
						if f < 7 and sqs[sq + 1] == (WHITE + PAWN) then
							mgDiff = mgDiff + 8
							egDiff = egDiff + 10
						end
					elseif pType == BISHOP then
						wBishops = wBishops + 1
					elseif pType == ROOK then
						wRooks = wRooks + 1
						wRookSquares[wRooks] = sq
						if r == 6 then
							mgDiff = mgDiff + 24
							egDiff = egDiff + 36
						end
					elseif pType == KNIGHT then
						if r >= 3 and r <= 5 and f >= 1 and f <= 6 then
							if sqs[sq - 17] == (WHITE + PAWN) or sqs[sq - 15] == (WHITE + PAWN) then
								mgDiff = mgDiff + 20
								egDiff = egDiff + 14
							end
						end
					end
				else
					if pType == PAWN then
						bPawnCount[f] = bPawnCount[f] + 1
						if r < bPawnMinRank[f] then bPawnMinRank[f] = r end
						if f < 7 and sqs[sq + 1] == (BLACK + PAWN) then
							mgDiff = mgDiff - 8
							egDiff = egDiff - 10
						end
					elseif pType == BISHOP then
						bBishops = bBishops + 1
					elseif pType == ROOK then
						bRooks = bRooks + 1
						bRookSquares[bRooks] = sq
						if r == 1 then
							mgDiff = mgDiff - 24
							egDiff = egDiff - 36
						end
					elseif pType == KNIGHT then
						if r >= 2 and r <= 4 and f >= 1 and f <= 6 then
							if sqs[sq + 17] == (BLACK + PAWN) or sqs[sq + 15] == (BLACK + PAWN) then
								mgDiff = mgDiff - 20
								egDiff = egDiff - 14
							end
						end
					end
				end
			end
		end
	end

	if wBishops >= 2 then mgDiff = mgDiff + 34 egDiff = egDiff + 54 end
	if bBishops >= 2 then mgDiff = mgDiff - 34 egDiff = egDiff - 54 end

	for i = 1, wRooks do
		local rf = band(wRookSquares[i], 7)
		if wPawnCount[rf] == 0 then
			if bPawnCount[rf] == 0 then
				mgDiff = mgDiff + 28 egDiff = egDiff + 15
			else
				mgDiff = mgDiff + 15 egDiff = egDiff + 8
			end
		end
	end
	for i = 1, bRooks do
		local rf = band(bRookSquares[i], 7)
		if bPawnCount[rf] == 0 then
			if wPawnCount[rf] == 0 then
				mgDiff = mgDiff - 28 egDiff = egDiff - 15
			else
				mgDiff = mgDiff - 15 egDiff = egDiff - 8
			end
		end
	end

	for f = 0, 7 do
		local wc = wPawnCount[f]
		if wc > 0 then
			if wc > 1 then
				mgDiff = mgDiff - (wc - 1) * 12
				egDiff = egDiff - (wc - 1) * 22
			end
			local lw = (f > 0) and wPawnCount[f - 1] or 0
			local rw = (f < 7) and wPawnCount[f + 1] or 0
			if lw == 0 and rw == 0 then
				mgDiff = mgDiff - 14
				egDiff = egDiff - 20
			end
			local maxR = wPawnMaxRank[f]
			local bMid = bPawnMinRank[f]
			local bLeft = (f > 0) and bPawnMinRank[f - 1] or 8
			local bRight = (f < 7) and bPawnMinRank[f + 1] or 8
			local blocked = false
			if bMid > maxR and bMid < 8 then blocked = true end
			if not blocked and bLeft > maxR and bLeft < 8 then blocked = true end
			if not blocked and bRight > maxR and bRight < 8 then blocked = true end
			if not blocked then
				local bonus = PASSED_BONUS_EG[maxR] or 0
				mgDiff = mgDiff + rshift(bonus, 1)
				egDiff = egDiff + bonus
			end
		end

		local bc = bPawnCount[f]
		if bc > 0 then
			if bc > 1 then
				mgDiff = mgDiff + (bc - 1) * 12
				egDiff = egDiff + (bc - 1) * 22
			end
			local lb = (f > 0) and bPawnCount[f - 1] or 0
			local rb = (f < 7) and bPawnCount[f + 1] or 0
			if lb == 0 and rb == 0 then
				mgDiff = mgDiff + 14
				egDiff = egDiff + 20
			end
			local minR = bPawnMinRank[f]
			local wMid = wPawnMaxRank[f]
			local wLeft = (f > 0) and wPawnMaxRank[f - 1] or -1
			local wRight = (f < 7) and wPawnMaxRank[f + 1] or -1
			local blocked = false
			if wMid >= 0 and wMid < minR then blocked = true end
			if not blocked and wLeft >= 0 and wLeft < minR then blocked = true end
			if not blocked and wRight >= 0 and wRight < minR then blocked = true end
			if not blocked then
				local bonus = PASSED_BONUS_EG[7 - minR] or 0
				mgDiff = mgDiff - rshift(bonus, 1)
				egDiff = egDiff - bonus
			end
		end
	end

	local wk = board.kingSq[WHITE]
	local bk = board.kingSq[BLACK]
	local wkf, wkr = band(wk, 7), rshift(wk, 4)
	local bkf, bkr = band(bk, 7), rshift(bk, 4)

	if gamePhase >= 10 then
		if wkr <= 1 and (wkf <= 2 or wkf >= 5) then
			if wPawnCount[wkf] == 0 then mgDiff = mgDiff - 24 end
		end
		if bkr >= 6 and (bkf <= 2 or bkf >= 5) then
			if bPawnCount[bkf] == 0 then mgDiff = mgDiff + 24 end
		end
	elseif gamePhase <= 6 then
		local kingDist = math.abs(wkf - bkf) + math.abs(wkr - bkr)
		if egDiff > 200 then
			local bCenter = math.abs(bkf - 3.5) + math.abs(bkr - 3.5)
			egDiff = egDiff + math.floor(bCenter * 15) + (14 - kingDist) * 8
		elseif egDiff < -200 then
			local wCenter = math.abs(wkf - 3.5) + math.abs(wkr - 3.5)
			egDiff = egDiff - math.floor(wCenter * 15) - (14 - kingDist) * 8
		end
	end

	local egPhase = 24 - gamePhase
	local totalScore = math.floor((mgDiff * gamePhase + egDiff * egPhase) / 24)
	if board.side == WHITE then
		return totalScore + 14
	else
		return -totalScore + 14
	end
end

--==============================================================================
-- 3. MASSIVE GM OPENING BOOK (Covers 1.e4, 1.d4, 1.Nf3, 1.c4, Dutch f5, etc.)
--==============================================================================
local OPENING_BOOK = {
	["rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w"] = { "e2e4", "d2d4", "g1f3", "c2c4" },
	-- 1. e4
	["rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b"] = { "c7c5", "e7e5", "e7e6", "c7c6" },
	["rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w"] = { "g1f3", "b1c3" },
	["rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b"] = { "d7d6", "b8c6", "e7e6" },
	["rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w"] = { "d2d4" },
	["rnbqkbnr/pp2pppp/3p4/2p5/3PP3/5N2/PPP2PPP/RNBQKB1R b"] = { "c5d4" },
	["rnbqkbnr/pp2pppp/3p4/8/3pP3/5N2/PPP2PPP/RNBQKB1R w"] = { "f3d4" },
	["rnbqkbnr/pp2pppp/3p4/8/3NP3/8/PPP2PPP/RNBQKB1R b"] = { "g8f6" },
	["rnbqkb1r/pp2pppp/3p1n2/8/3NP3/8/PPP2PPP/RNBQKB1R w"] = { "b1c3" },
	["rnbqkb1r/pp2pppp/3p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R b"] = { "a7a6", "b8c6" },
	["rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w"] = { "g1f3" },
	["rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b"] = { "b8c6", "g8f6" },
	["r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w"] = { "f1b5", "f1c4", "d2d4" },
	["r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b"] = { "a7a6", "g8f6" },
	["r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w"] = { "b5a4", "b5c6" },
	["r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b"] = { "f8c5", "g8f6" },
	["r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w"] = { "c2c3", "d2d3", "e1g1" },
	-- 1. d4
	["rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b"] = { "g8f6", "d7d5" },
	["rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w"] = { "c2c4", "g1f3" },
	["rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b"] = { "e7e6", "c7c6" },
	["rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w"] = { "c2c4", "g1f3" },
	["rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b"] = { "e7e6", "g7g6", "d7d5" },
	["rnbqkbnr/ppppp1pp/8/5p2/3P4/8/PPP1PPPP/RNBQKBNR w"] = { "c2c4", "g1f3", "g2g3" },
	-- 1. Nf3 (Zukertort Opening — including 1. Nf3 f5 from screenshot!)
	["rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b"] = { "d7d5", "g8f6", "c7c5" },
	["rnbqkbnr/ppppp1pp/8/5p2/8/5N2/PPPPPPPP/RNBQKB1R w"] = { "d2d4", "c2c4", "g2g3", "d2d3" },
	["rnbqkbnr/ppppp1pp/8/5p2/3P4/5N2/PPP1PPPP/RNBQKB1R b"] = { "g8f6", "e7e6", "d7d6" },
	["rnbqkbnr/ppp1pppp/8/3p4/8/5N2/PPPPPPPP/RNBQKB1R w"] = { "d2d4", "c2c4", "g2g3" },
	["rnbqkb1r/pppppppp/5n2/8/8/5N2/PPPPPPPP/RNBQKB1R w"] = { "c2c4", "d2d4", "g2g3" },
	["rnbqkbnr/pp1ppppp/8/2p5/8/5N2/PPPPPPPP/RNBQKB1R w"] = { "c2c4", "e2e4", "g2g3" },
	-- 1. c4
	["rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b"] = { "e7e5", "g8f6", "c7c5" },
}

local function probeBook(fenKey)
	local list = OPENING_BOOK[fenKey]
	if list and #list > 0 then
		return list[math.random(1, #list)]
	end
	return nil
end

--==============================================================================
-- 4. STOCKFISH TIMEMAN.CPP (Optimum & Maximum Time + Instability Scaling)
--==============================================================================
-- ประเมินจำนวนตาเดินจริงจากสภาพกระดาน (แก้ปัญหา State.full เป็น nil หรือค้างที่ 1 ใน ChessDuels)
local START_BOARD_TEMPLATE = {
	 4,  2,  3,  5,  6,  3,  2,  4,
	 1,  1,  1,  1,  1,  1,  1,  1,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	-1, -1, -1, -1, -1, -1, -1, -1,
	-4, -2, -3, -5, -6, -3, -2, -4,
}

local function estimateTrueMoveNumber(State, isTopDown)
	local rawFull = tonumber(State.full) or tonumber(State.fullmove) or tonumber(State.moveCount)
	if rawFull and rawFull > 1 then
		return rawFull
	end
	if type(State.history) == "table" and #State.history > 0 then
		return math.floor(#State.history / 2) + 1
	end
	if type(State.moves) == "table" and #State.moves > 0 then
		return math.floor(#State.moves / 2) + 1
	end

	-- นับจำนวนช่องที่เปลี่ยนไปจากตำแหน่งเริ่มต้น + ตัวหมากที่ถูกกิน
	local changed = 0
	local pieceCount = 0
	for idx64 = 1, 64 do
		local v = State.board[idx64] or 0
		if v ~= 0 then pieceCount = pieceCount + 1 end
		local row0 = math.floor((idx64 - 1) / 8)
		local f0   = (idx64 - 1) % 8
		local r0   = isTopDown and (7 - row0) or row0
		local stdIdx = r0 * 8 + f0 + 1
		if v ~= START_BOARD_TEMPLATE[stdIdx] then
			changed = changed + 1
		end
	end
	local captured = math.max(0, 32 - pieceCount)
	local estFull = math.floor(changed / 3.2) + captured + 1
	return math.clamp(estFull, 1, 60)
end

local function computeStockfishTime(remainingSec, moveNumber)
	remainingSec = tonumber(remainingSec) or 60
	moveNumber   = tonumber(moveNumber) or 10
	local safeRem = math.max(0.04, remainingSec - 0.040)

	if safeRem < 5.0 then
		return math.clamp(safeRem * 0.035, 0.015, 0.045), math.clamp(safeRem * 0.09, 0.025, 0.080)
	elseif safeRem <= 15.0 then
		return math.clamp(safeRem * 0.045, 0.030, 0.085), math.clamp(safeRem * 0.11, 0.055, 0.150)
	elseif safeRem <= 65.0 then
		local mtg = math.max(20, 36 - math.floor(moveNumber * 0.35))
		local opt = safeRem / mtg
		return math.clamp(opt, 0.080, 0.420), math.clamp(opt * 2.2, 0.140, 0.750)
	elseif safeRem <= 200.0 then
		local mtg = math.max(18, 34 - math.floor(moveNumber * 0.3))
		local opt = safeRem / mtg
		if moveNumber >= 8 and moveNumber <= 24 then opt = opt * 1.25 end
		return math.clamp(opt, 0.220, 1.450), math.clamp(opt * 2.4, 0.400, 2.600)
	else
		local mtg = math.max(16, 30 - math.floor(moveNumber * 0.25))
		local opt = safeRem / mtg
		if moveNumber >= 8 and moveNumber <= 28 then opt = opt * 1.30 end
		return math.clamp(opt, 0.450, 3.600), math.clamp(opt * 2.6, 0.900, 7.000)
	end
end

--==============================================================================
-- 5. STOCKFISH SEARCH ENGINE (LMR ln(d)*ln(m) + SEE + Gravity History + PVS)
--==============================================================================
local INF     = 30000
local MATE    = 29000
local MAX_PLY = 64

local TT_SIZE = 262144
local TT_MASK = TT_SIZE - 1

local TT_EXACT = 1
local TT_ALPHA = 2
local TT_BETA  = 3

local ttHashLo = table.create(TT_SIZE, 0)
local ttHashHi = table.create(TT_SIZE, 0)
local ttMove   = table.create(TT_SIZE, 0)
local ttScore  = table.create(TT_SIZE, 0)
local ttDepth  = table.create(TT_SIZE, -1)
local ttFlag   = table.create(TT_SIZE, 0)

-- Precomputed Stockfish LMR Logarithmic Table: R = floor(0.75 + ln(d) * ln(m) / 2.25)
local LMR_TABLE = {}
for d = 1, 64 do
	LMR_TABLE[d] = table.create(64, 0)
	for m = 1, 64 do
		LMR_TABLE[d][m] = math.floor(0.75 + (math.log(d) * math.log(m)) / 2.25)
	end
end

local killer1    = table.create(MAX_PLY, 0)
local killer2    = table.create(MAX_PLY, 0)
local staticEvalStack = table.create(MAX_PLY, 0)
local counterMoveTable = {}
local historyTable     = {}
local MAX_HISTORY      = 16384

for s = 0, 8, 8 do
	historyTable[s]     = {}
	counterMoveTable[s] = {}
	for from = 0, 127 do
		historyTable[s][from]     = table.create(128, 0)
		counterMoveTable[s][from] = table.create(128, 0)
	end
end

-- Stockfish Gravity History Update Formula (`src/history.h`):
-- score += bonus - score * abs(bonus) / 16384
local function updateHistoryGravity(side, from, to, bonus)
	local row = historyTable[side][from]
	local cur = row[to] or 0
	local clampedBonus = math.clamp(bonus, -MAX_HISTORY, MAX_HISTORY)
	row[to] = math.floor(cur + clampedBonus - (cur * math.abs(clampedBonus)) / MAX_HISTORY)
end

local function clearKillers()
	for i = 1, MAX_PLY do
		killer1[i] = 0
		killer2[i] = 0
		staticEvalStack[i] = 0
	end
end

-- Stockfish MovePicker Staging:
-- 1. TT Move (2,000,000)
-- 2. Good Captures SEE >= 0 (1,000,000 + MVV-LVA)
-- 3. Promotions (900,000)
-- 4. Killer 1 (800,000) & Killer 2 (750,000)
-- 5. Countermove (700,000)
-- 6. Quiet Moves by Gravity History (-16384 .. +16384)
-- 7. Bad Captures SEE < 0 (-500,000 + SEE)
local function scoreMovesStockfish(board, moves, n, ply, hashMove, prevMove)
	local scores = table.create(n, 0)
	local sqs    = board.squares
	local side   = board.side
	local opp    = bxor(side, 8)
	local k1     = killer1[ply]
	local k2     = killer2[ply]
	local cm     = 0
	if prevMove and prevMove ~= 0 then
		local pf = band(prevMove, 0x7F)
		local pt = band(rshift(prevMove, 7), 0x7F)
		cm = counterMoveTable[side][pf][pt] or 0
	end
	local histSide = historyTable[side]

	for i = 1, n do
		local m = moves[i]
		if m == hashMove then
			scores[i] = 2000000
		else
			local cap   = band(rshift(m, 14), 0xF)
			local promo = band(rshift(m, 18), 0x7)
			if cap ~= 0 then
				local from     = band(m, 0x7F)
				local to       = band(rshift(m, 7), 0x7F)
				local attacker = band(sqs[from], 7)
				local victim   = band(cap, 7)
				local gain     = (SEE_VALUE[victim] or 100) + ((promo ~= 0) and (SEE_VALUE[promo] - 100) or 0)
				local risk     = SEE_VALUE[attacker] or 100

				-- Fast SEE check: if attacker is worth more than victim and square is defended by opponent
				local seeScore = gain
				if risk > gain then
					local oppLVA = board:getLeastValuableAttacker(to, opp)
					if oppLVA ~= 0 then
						seeScore = gain - risk
					end
				end

				if seeScore >= 0 then
					scores[i] = 1000000 + gain * 12 - risk
				else
					scores[i] = -500000 + seeScore
				end
			elseif promo ~= 0 then
				scores[i] = 900000 + promo * 100
			elseif m == k1 then
				scores[i] = 800000
			elseif m == k2 then
				scores[i] = 750000
			elseif m == cm and cm ~= 0 then
				scores[i] = 700000
			else
				local from = band(m, 0x7F)
				local to   = band(rshift(m, 7), 0x7F)
				scores[i]  = histSide[from][to] or 0
			end
		end
	end
	return scores
end

local function pickNextMove(moves, scores, n, startIdx)
	local bestIdx = startIdx
	local bestScore = scores[startIdx]
	for i = startIdx + 1, n do
		if scores[i] > bestScore then
			bestScore = scores[i]
			bestIdx = i
		end
	end
	if bestIdx ~= startIdx then
		moves[startIdx], moves[bestIdx] = moves[bestIdx], moves[startIdx]
		scores[startIdx], scores[bestIdx] = scores[bestIdx], scores[startIdx]
	end
	return moves[startIdx], bestScore
end

local Searcher = {
	nodes          = 0,
	aborted        = false,
	startTime      = 0,
	optLimit       = 0.2,
	maxLimit       = 0.5,
	lastYieldClock = 0,
	frameBudgetSec = 0.012,
	allowYield     = true,
}

local function checkTimeAndYield()
	local now = os.clock()
	if (now - Searcher.startTime) >= Searcher.maxLimit then
		Searcher.aborted = true
		return true
	end
	if Searcher.allowYield and (now - Searcher.lastYieldClock) >= Searcher.frameBudgetSec then
		if (Searcher.maxLimit - (now - Searcher.startTime)) > 0.065 then
			task.wait()
			Searcher.lastYieldClock = os.clock()
			if (Searcher.lastYieldClock - Searcher.startTime) >= Searcher.maxLimit then
				Searcher.aborted = true
				return true
			end
		else
			Searcher.lastYieldClock = now
		end
	end
	return false
end

local function quiescence(board, alpha, beta, ply)
	Searcher.nodes = Searcher.nodes + 1
	if band(Searcher.nodes, 511) == 0 then
		if checkTimeAndYield() then return 0 end
	end

	local standPat = evaluate(board)
	if standPat >= beta then return beta end
	if standPat > alpha then alpha = standPat end
	if ply >= MAX_PLY then return standPat end
	if standPat + 1050 < alpha then return alpha end

	local moves, n = board:generateMoves(true)
	if n == 0 then return alpha end

	local scores = scoreMovesStockfish(board, moves, n, ply, 0, 0)
	for i = 1, n do
		local m, mScore = pickNextMove(moves, scores, n, i)
		-- SEE Pruning in Quiescence: skip losing captures (mScore < -100000)
		if mScore < -100000 then break end

		if board:makeMove(m) then
			local score = -quiescence(board, -beta, -alpha, ply + 1)
			board:unmakeMove()
			if Searcher.aborted then return 0 end
			if score >= beta then return beta end
			if score > alpha then alpha = score end
		end
	end
	return alpha
end

local function negamax(board, depth, alpha, beta, ply, allowNull, prevMove)
	Searcher.nodes = Searcher.nodes + 1
	if band(Searcher.nodes, 511) == 0 then
		if checkTimeAndYield() then return 0 end
	end

	local isRoot = (ply == 1)
	local pvNode = (beta - alpha > 1)

	-- Step 2 & 3: Draw Check & Mate Distance Pruning
	if not isRoot then
		if board.halfmove >= 100 then return 0 end
		local hLo, hHi = board.hashLo, board.hashHi
		for idx = board.ply - 2, 1, -2 do
			local h = board.history[idx]
			if h and h.hashLo == hLo and h.hashHi == hHi then
				return 0
			end
		end

		local rAlpha = math.max(alpha, -MATE + ply)
		local rBeta  = math.min(beta, MATE - ply - 1)
		if rAlpha >= rBeta then return rAlpha end
	end

	local inChk = board:inCheck(board.side)
	if inChk then depth = depth + 1 end

	if depth <= 0 or ply >= MAX_PLY then
		return quiescence(board, alpha, beta, ply)
	end

	-- Step 4 & 6: Transposition Table Lookup
	local ttIdx = band(board.hashLo, TT_MASK) + 1
	local hashMove = 0
	if ttDepth[ttIdx] >= 0 and ttHashLo[ttIdx] == board.hashLo and ttHashHi[ttIdx] == board.hashHi then
		hashMove = ttMove[ttIdx]
		if not pvNode and ttDepth[ttIdx] >= depth then
			local tScore = ttScore[ttIdx]
			if tScore > MATE - 100 then tScore = tScore - ply
			elseif tScore < -MATE + 100 then tScore = tScore + ply end

			local flag = ttFlag[ttIdx]
			if flag == TT_EXACT then return tScore
			elseif flag == TT_ALPHA and tScore <= alpha then return alpha
			elseif flag == TT_BETA and tScore >= beta then return beta end
		end
	end

	-- Step 11: Internal Iterative Reductions (IIR)
	if depth >= 4 and hashMove == 0 then
		depth = depth - 1
	end

	local staticEval = evaluate(board)
	staticEvalStack[ply] = staticEval
	local improving = (ply > 2) and (staticEval > (staticEvalStack[ply - 2] or -INF)) or false

	if not pvNode and not inChk and math.abs(beta) < MATE - 100 then
		-- Step 8: Razoring
		if depth <= 2 and (staticEval + 280 * depth) <= alpha then
			return quiescence(board, alpha, beta, ply)
		end

		-- Step 9: Reverse Futility Pruning (with Stockfish `improving` adjustment)
		if depth <= 4 then
			local margin = (improving and 85 or 115) * depth
			if staticEval - margin >= beta then
				return staticEval - margin
			end
		end

		-- Step 10: Null Move Pruning (R = 3 + depth / 4)
		if allowNull and depth >= 3 and board.phase > 2 and staticEval >= beta then
			local prevEp = board.ep
			local prevLo, prevHi = board.hashLo, board.hashHi
			if prevEp ~= -1 then
				board.hashLo = bxor(board.hashLo, ZOBRIST_EP_LO[prevEp])
				board.hashHi = bxor(board.hashHi, ZOBRIST_EP_HI[prevEp])
			end
			board.side = bxor(board.side, 8)
			board.ep = -1
			board.hashLo = bxor(board.hashLo, ZOBRIST_SIDE_LO)
			board.hashHi = bxor(board.hashHi, ZOBRIST_SIDE_HI)

			local R = 3 + rshift(depth, 2)
			local nullScore = -negamax(board, depth - 1 - R, -beta, -beta + 1, ply + 1, false, 0)

			board.side = bxor(board.side, 8)
			board.ep = prevEp
			board.hashLo, board.hashHi = prevLo, prevHi

			if Searcher.aborted then return 0 end
			if nullScore >= beta then return beta end
		end
	end

	local moves, n = board:generateMoves(false)
	local scores = scoreMovesStockfish(board, moves, n, ply, hashMove, prevMove)

	local legalMoves = 0
	local origAlpha  = alpha
	local bestScore  = -INF
	local bestMove   = 0
	local quietsTried = {}
	local nQuiets     = 0

	for i = 1, n do
		local m, mOrderScore = pickNextMove(moves, scores, n, i)
		local cap   = band(rshift(m, 14), 0xF)
		local promo = band(rshift(m, 18), 0x7)
		local isQuiet = (cap == 0 and promo == 0)

		-- Step 15: Late Move Pruning (LMP) & Futility Pruning at shallow depths
		local skipMove = false
		if not isRoot and not pvNode and not inChk and isQuiet and bestScore > -MATE + 100 then
			if depth <= 3 and legalMoves >= (4 + depth * depth * (improving and 2 or 1)) then
				skipMove = true
			elseif depth <= 2 and (staticEval + 130 * depth) <= alpha and mOrderScore < 50000 then
				skipMove = true
			end
		end

		if not skipMove and board:makeMove(m) then
			legalMoves = legalMoves + 1
			if isQuiet then
				nQuiets = nQuiets + 1
				quietsTried[nQuiets] = m
			end

			local score
			if legalMoves == 1 then
				score = -negamax(board, depth - 1, -beta, -alpha, ply + 1, true, m)
			else
				-- Step 18: Stockfish Logarithmic Late Move Reductions (LMR)
				local reduction = 0
				if depth >= 3 and legalMoves >= 3 and isQuiet and not inChk then
					local dIdx = math.min(64, depth)
					local mIdx = math.min(64, legalMoves)
					reduction = LMR_TABLE[dIdx][mIdx] or 1
					if pvNode then reduction = reduction - 1 end
					if improving then reduction = reduction - 1 end
					if mOrderScore >= 700000 then reduction = reduction - 1 end -- Killer / Countermove
					reduction = math.clamp(reduction, 0, depth - 2)
				end

				-- Step 19 & 20: Principal Variation Search (PVS)
				score = -negamax(board, depth - 1 - reduction, -alpha - 1, -alpha, ply + 1, true, m)
				if score > alpha and reduction > 0 then
					score = -negamax(board, depth - 1, -alpha - 1, -alpha, ply + 1, true, m)
				end
				if score > alpha and score < beta then
					score = -negamax(board, depth - 1, -beta, -alpha, ply + 1, true, m)
				end
			end

			board:unmakeMove()
			if Searcher.aborted then return 0 end

			if score > bestScore then
				bestScore = score
				bestMove  = m
				if score > alpha then
					alpha = score
					if alpha >= beta then
						-- Beta Cutoff: Gravity History Bonus for best quiet move + Penalty for failed quiets!
						if isQuiet then
							if killer1[ply] ~= m then
								killer2[ply] = killer1[ply]
								killer1[ply] = m
							end
							local bonus = math.min(1800, depth * depth * 16)
							local bf = band(m, 0x7F)
							local bt = band(rshift(m, 7), 0x7F)
							updateHistoryGravity(board.side, bf, bt, bonus)

							for q = 1, nQuiets - 1 do
								local qm = quietsTried[q]
								updateHistoryGravity(board.side, band(qm, 0x7F), band(rshift(qm, 7), 0x7F), -bonus)
							end

							if prevMove and prevMove ~= 0 then
								local pf = band(prevMove, 0x7F)
								local pt = band(rshift(prevMove, 7), 0x7F)
								counterMoveTable[board.side][pf][pt] = m
							end
						end
						break
					end
				end
			end
		end
	end

	if legalMoves == 0 then
		if inChk then return -MATE + ply else return 0 end
	end

	if not Searcher.aborted then
		local storeScore = bestScore
		if storeScore > MATE - 100 then storeScore = storeScore + ply
		elseif storeScore < -MATE + 100 then storeScore = storeScore - ply end

		if ttDepth[ttIdx] <= depth + 2 or ttHashLo[ttIdx] == board.hashLo then
			ttHashLo[ttIdx] = board.hashLo
			ttHashHi[ttIdx] = board.hashHi
			ttMove[ttIdx]   = bestMove
			ttScore[ttIdx]  = storeScore
			ttDepth[ttIdx]  = depth
			if bestScore <= origAlpha then
				ttFlag[ttIdx] = TT_ALPHA
			elseif bestScore >= beta then
				ttFlag[ttIdx] = TT_BETA
			else
				ttFlag[ttIdx] = TT_EXACT
			end
		end
	end

	return bestScore, bestMove
end

--==============================================================================
-- 6. EXACT CHESSDUELS 1..64 MAPPER + MULTI-CHOICE FALLBACK (ZERO MID-GAME FREEZE)
--==============================================================================
local PIECE_TO_CHAR = {
	[1] = "P", [2] = "N", [3] = "B", [4] = "R", [5] = "Q", [6] = "K",
	[-1] = "p", [-2] = "n", [-3] = "b", [-4] = "r", [-5] = "q", [-6] = "k",
}

-- In ChessDuels, State.board[1..64] ALWAYS maps 1..8 = Rank 1 (a1..h1) and 57..64 = Rank 8 (a8..h8)
local function sq0x88ToIdx64(sq)
	local r0 = rshift(sq, 4) -- 0..7 (Rank 1..8)
	local f0 = band(sq, 7)   -- 0..7 (File a..h)
	return r0 * 8 + f0 + 1
end

local START_BOARD_TEMPLATE = {
	 4,  2,  3,  5,  6,  3,  2,  4,
	 1,  1,  1,  1,  1,  1,  1,  1,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	 0,  0,  0,  0,  0,  0,  0,  0,
	-1, -1, -1, -1, -1, -1, -1, -1,
	-4, -2, -3, -5, -6, -3, -2, -4,
}

local function estimateTrueMoveNumber(State)
	local rawFull = tonumber(State.full) or tonumber(State.fullmove) or tonumber(State.moveCount)
	if rawFull and rawFull > 1 then
		return rawFull
	end
	if type(State.history) == "table" and #State.history > 0 then
		return math.floor(#State.history / 2) + 1
	end
	if type(State.moves) == "table" and #State.moves > 0 then
		return math.floor(#State.moves / 2) + 1
	end

	local changed = 0
	local pieceCount = 0
	for idx64 = 1, 64 do
		local v = State.board[idx64] or 0
		if v ~= 0 then pieceCount = pieceCount + 1 end
		if v ~= START_BOARD_TEMPLATE[idx64] then
			changed = changed + 1
		end
	end
	local captured = math.max(0, 32 - pieceCount)
	local estFull = math.floor(changed / 3.2) + captured + 1
	return math.clamp(estFull, 1, 60)
end

local function decodePackedToChessDuels(m, isWhiteTurn)
	local from0x88  = band(m, 0x7F)
	local to0x88    = band(rshift(m, 7), 0x7F)
	local promoCode = band(rshift(m, 18), 0x7)
	-- In ChessDuels, Queen=5, Rook=4, Bishop=3, Knight=2 (or 0 if no promotion)
	local promoVal  = (promoCode ~= 0) and promoCode or 0
	return {
		from  = sq0x88ToIdx64(from0x88),
		to    = sq0x88ToIdx64(to0x88),
		promo = promoVal,
	}
end

local function computeBestMove(State, remainingSec)
	local b = newBoard()
	local sqs = b.squares

	for idx64 = 1, 64 do
		local v = State.board[idx64] or 0
		if v ~= 0 then
			local r0 = math.floor((idx64 - 1) / 8)
			local f0 = (idx64 - 1) % 8
			local sq0x88 = lshift(r0, 4) + f0
			local pCode = (v > 0) and v or (8 + (-v))
			sqs[sq0x88] = pCode
			if math.abs(v) == 6 then
				b.kingSq[(v > 0) and 0 or 8] = sq0x88
			end
		end
	end

	local isWhiteTurn = (State.turn == 1 or State.turn == "w" or State.turn == "White" or State.turn == true)
	b.side     = isWhiteTurn and WHITE or BLACK
	b.halfmove = tonumber(State.half) or 0
	b.fullmove = estimateTrueMoveNumber(State)

	-- Parse Castling Rights safely (also verify King and Rook are actually on their starting squares!)
	local cr = 0
	if type(State.castle) == "table" then
		local cw = State.castle[1] or State.castle.w or State.castle.W
		local cb = State.castle[-1] or State.castle.b or State.castle.B
		if type(cw) == "table" then
			if cw.k or cw.K or cw[1] then cr = bor(cr, 1) end
			if cw.q or cw.Q or cw[2] then cr = bor(cr, 2) end
		end
		if type(cb) == "table" then
			if cb.k or cb.K or cb[1] then cr = bor(cr, 4) end
			if cb.q or cb.Q or cb[2] then cr = bor(cr, 8) end
		end
		if cr == 0 then
			if State.castle.K or State.castle.wk or State.castle[1] == true then cr = bor(cr, 1) end
			if State.castle.Q or State.castle.wq or State.castle[2] == true then cr = bor(cr, 2) end
			if State.castle.k or State.castle.bk or State.castle[3] == true then cr = bor(cr, 4) end
			if State.castle.q or State.castle.bq or State.castle[4] == true then cr = bor(cr, 8) end
		end
	end
	-- Strictly verify King & Rook positions so we never generate an illegal castle
	if sqs[4] ~= (WHITE + KING) then cr = band(cr, 15 - 3) end
	if sqs[7] ~= (WHITE + ROOK) then cr = band(cr, 15 - 1) end
	if sqs[0] ~= (WHITE + ROOK) then cr = band(cr, 15 - 2) end
	if sqs[116] ~= (BLACK + KING) then cr = band(cr, 15 - 12) end
	if sqs[119] ~= (BLACK + ROOK) then cr = band(cr, 15 - 4) end
	if sqs[112] ~= (BLACK + ROOK) then cr = band(cr, 15 - 8) end
	b.castling = cr

	if type(State.ep) == "number" and State.ep >= 1 and State.ep <= 64 then
		local er0 = math.floor((State.ep - 1) / 8)
		local ef0 = (State.ep - 1) % 8
		b.ep = lshift(er0, 4) + ef0
	else
		b.ep = -1
	end

	b:recomputeState()

	-- Generate all legal root moves first
	local rawMoves, n = b:generateMoves(false)
	local legalRootMoves = {}
	for i = 1, n do
		if b:makeMove(rawMoves[i]) then
			table.insert(legalRootMoves, rawMoves[i])
			b:unmakeMove()
		end
	end

	if #legalRootMoves == 0 then return nil end

	-- Build FEN key for GM Opening Book
	local ranks = {}
	for r0 = 7, 0, -1 do
		local empty = 0
		local s = ""
		for f0 = 0, 7 do
			local p = sqs[lshift(r0, 4) + f0]
			if p == EMPTY then
				empty = empty + 1
			else
				if empty > 0 then s = s .. tostring(empty) empty = 0 end
				local signedP = (band(p, 8) == WHITE) and band(p, 7) or -band(p, 7)
				s = s .. (PIECE_TO_CHAR[signedP] or "P")
			end
		end
		if empty > 0 then s = s .. tostring(empty) end
		table.insert(ranks, s)
	end
	local fenKey = table.concat(ranks, "/") .. " " .. (isWhiteTurn and "w" or "b")

	-- 1. Probe GM Opening Book (match against actual legalRootMoves so it is 100% legal!)
	local bookUCI = (b.fullmove <= 5) and probeBook(fenKey) or nil
	if bookUCI and #bookUCI >= 4 then
		local fromSq = algebraicToSq(string.sub(bookUCI, 1, 2))
		local toSq   = algebraicToSq(string.sub(bookUCI, 3, 4))
		for _, lm in ipairs(legalRootMoves) do
			if band(lm, 0x7F) == fromSq and band(rshift(lm, 7), 0x7F) == toSq then
				local res = decodePackedToChessDuels(lm, isWhiteTurn)
				res.isBook     = true
				res.isForced   = false
				res.complexity = 1
				res.moveNum    = b.fullmove
				res.altMove    = (#legalRootMoves > 1) and decodePackedToChessDuels(legalRootMoves[1], isWhiteTurn) or nil
				return res
			end
		end
	end

	local optLimit, maxLimit = computeStockfishTime(remainingSec, b.fullmove)
	Searcher.nodes          = 0
	Searcher.aborted        = false
	Searcher.startTime      = os.clock()
	Searcher.lastYieldClock = Searcher.startTime
	Searcher.optLimit       = optLimit
	Searcher.maxLimit       = maxLimit
	Searcher.allowYield     = (maxLimit > 0.080)

	clearKillers()

	local bestMove     = legalRootMoves[1]
	local secondMove   = legalRootMoves[2] or legalRootMoves[1]
	local bestScore    = 0
	local prevBestMove = 0
	local stabilityCnt = 0

	if #legalRootMoves > 1 then
		for depth = 1, 32 do
			local score, move
			if depth >= 4 then
				local delta = 25
				local alpha = math.max(-INF, bestScore - delta)
				local beta  = math.min(INF, bestScore + delta)
				while true do
					score, move = negamax(b, depth, alpha, beta, 1, false, 0)
					if Searcher.aborted then break end
					if score <= alpha then
						beta  = math.floor((alpha + beta) / 2)
						alpha = math.max(-INF, alpha - delta)
						delta = delta * 2
					elseif score >= beta then
						beta  = math.min(INF, beta + delta)
						delta = delta * 2
					else
						break
					end
				end
			else
				score, move = negamax(b, depth, -INF, INF, 1, false, 0)
			end

			if Searcher.aborted then break end
			if move and move ~= 0 then
				if move ~= bestMove then
					secondMove = bestMove
				end
				if move == prevBestMove then
					stabilityCnt = stabilityCnt + 1
				else
					stabilityCnt = 0
					prevBestMove = move
				end
				bestMove  = move
				bestScore = score
			end

			if math.abs(bestScore) >= MATE - 100 then break end

			local stabilityFactor = (stabilityCnt >= 3) and 0.50 or ((stabilityCnt == 0 and depth >= 5) and 0.90 or 0.68)
			if (os.clock() - Searcher.startTime) >= Searcher.optLimit * stabilityFactor then
				break
			end
		end
	end

	local isCaptureMove = (band(rshift(bestMove, 14), 0xF) ~= 0)
	local complexity = 2
	if #legalRootMoves == 1 then
		complexity = 0
	elseif stabilityCnt <= 1 or (#legalRootMoves >= 26 and b.phase >= 12) then
		complexity = 3
	elseif isCaptureMove and stabilityCnt >= 3 then
		complexity = 1
	end

	local res = decodePackedToChessDuels(bestMove, isWhiteTurn)
	res.isBook     = false
	res.isForced   = (#legalRootMoves == 1)
	res.complexity = complexity
	res.moveNum    = b.fullmove
	res.altMove    = (secondMove and secondMove ~= bestMove) and decodePackedToChessDuels(secondMove, isWhiteTurn) or nil
	return res
end

--==============================================================================
-- 7. ROBLOX CLIENT INTEGRATION (NEVER-STUCK WATCHDOG + BUILT-IN BOT BACKUP)
--==============================================================================
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local HttpService         = game:GetService("HttpService")
local GuiService          = game:GetService("GuiService")
local CoreGui             = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	task.wait(0.2)
	LocalPlayer = Players.LocalPlayer
end

local PlayMove = ReplicatedStorage:WaitForChild("ChessRemotes"):WaitForChild("Action")
local BuiltInBot = nil
pcall(function()
	local chessFolder = ReplicatedStorage:WaitForChild("Chess", 5)
	if chessFolder then
		local botMod = chessFolder:WaitForChild("Bot", 5)
		if botMod then BuiltInBot = require(botMod) end
	end
end)

-- Emergency Backup: If our move is ever rejected by the server on retry >= 2, ask the game's own Bot module for a 100% server-compatible move!
local function computeBackupMoveFromGameModule(State)
	if not BuiltInBot or type(BuiltInBot.analyze) ~= "function" then return nil end
	local WKing, BKing = 5, 61
	for i = 1, 64 do
		if State.board[i] == 6 then WKing = i
		elseif State.board[i] == -6 then BKing = i end
	end
	local VirtualGame = {
		board  = table.clone(State.board),
		turn   = State.turn,
		castle = type(State.castle) == "table" and table.clone(State.castle) or State.castle,
		ep     = State.ep,
		half   = State.half,
		full   = State.full,
		kings  = { [1] = WKing, [-1] = BKing },
	}
	local ok, _, mv = pcall(function()
		return BuiltInBot.analyze(VirtualGame, 4, 10)
	end)
	if ok and type(mv) == "table" and mv.from and mv.to then
		return mv
	end
	return nil
end

local createdScreenGui = nil

local function purgeLegacyUIs()
	local roots = {}
	pcall(function() if type(gethui) == "function" then table.insert(roots, gethui()) end end)
	pcall(function() table.insert(roots, CoreGui) end)
	pcall(function()
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then table.insert(roots, pg) end
	end)
	for _, root in ipairs(roots) do
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("ScreenGui") and child ~= createdScreenGui then
				local isOldBotUI = false
				for _, desc in ipairs(child:GetDescendants()) do
					if desc:IsA("TextLabel") or desc:IsA("TextButton") then
						local t = desc.Text or ""
						if string.find(t, "Sill ChessDuels (Full Auto)", 1, true)
							or string.find(t, "Zero-Lag • SILL X UI", 1, true)
							or string.find(t, "Bot Preset", 1, true)
						then
							isOldBotUI = true
							break
						end
					end
				end
				if isOldBotUI or (not createdScreenGui and string.find(string.lower(child.Name), "sill")) then
					pcall(function() child:Destroy() end)
				end
			end
		end
	end
end

purgeLegacyUIs()

local Settings = {
	AutoPlay   = true,
	HumanPace  = true,
	AutoQueue  = true,
	TimeMode   = "1 min",
}

local function normalizeTimeMode(val)
	local s = string.lower(tostring(val or ""))
	if string.find(s, "10") then return "10 min" end
	if string.find(s, "3") then return "3 min" end
	if string.find(s, "1") then return "1 min" end
	return "1 min"
end

local function saveSettings()
	if type(writefile) == "function" then
		pcall(function()
			writefile(STATE_FILE, HttpService:JSONEncode(Settings))
		end)
	end
end

local function loadSettings()
	if type(isfile) == "function" and type(readfile) == "function" then
		pcall(function()
			if isfile(STATE_FILE) then
				local data = HttpService:JSONDecode(readfile(STATE_FILE))
				if type(data) == "table" then
					for k, v in pairs(data) do
						if Settings[k] ~= nil then Settings[k] = v end
					end
					Settings.TimeMode = normalizeTimeMode(Settings.TimeMode)
				end
			else
				saveSettings()
			end
		end)
	end
end

loadSettings()

local function getQueueFunc()
	return (syn and syn.queue_on_teleport)
		or queue_on_teleport
		or (fluxus and fluxus.queue_on_teleport)
		or queueonteleport
		or (getgenv and (getgenv().queue_on_teleport or getgenv().queueonteleport))
end

local teleportConn = LocalPlayer.OnTeleport:Connect(function(state)
	saveSettings()
	if (state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress) and not ENV.SillChess_TeleportQueued then
		local qFunc = getQueueFunc()
		if qFunc then
			ENV.SillChess_TeleportQueued = true
			pcall(qFunc, [[
				repeat task.wait(0.2) until game:IsLoaded() and game:GetService("Players").LocalPlayer
				task.wait(1.0)
				if type(isfile) == "function" and isfile("]] .. AUTORUN_FILE .. [[") then
					loadfile("]] .. AUTORUN_FILE .. [[")()
				end
			]])
		end
	end
end)

local okUI, SilL = pcall(function()
	return loadstring(game:HttpGet("https://raw.githubusercontent.com/sillbuilt/Sill-UI/refs/heads/main/SilL-X-UI.lua"))()
end)

local Window = (okUI and SilL) and SilL:CreateWindow({
	Name = "Sill X | Solo 2800+ Bot ♟️",
	Subtitle = "Stockfish Brain • Anti-Freeze Watchdog",
	Theme = "Ocean",
	ToggleKey = Enum.KeyCode.RightShift,
	Size = UDim2.fromOffset(500, 340),
	Watermark = true,
	SettingsTab = true,
	Config = { Enabled = false }
}) or nil

createdScreenGui = Window and Window.Gui or nil
if createdScreenGui then
	createdScreenGui.Name = "SillX_Solo2800_Protected"
end

local trackedTextElements = {}

local function getScreenGuiOf(inst)
	local curr = inst.Parent
	while curr and curr ~= LocalPlayer do
		if curr:IsA("ScreenGui") then return curr end
		curr = curr.Parent
	end
	return nil
end

local function isOurOwnUI(inst)
	local sGui = getScreenGuiOf(inst)
	if not sGui then return false end
	if sGui == createdScreenGui or string.find(string.lower(sGui.Name), "sill") then return true end
	return false
end

local function registerTextElement(inst)
	if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and not isOurOwnUI(inst) then
		trackedTextElements[inst] = true
	end
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local descAddedConn, descRemovingConn
if playerGui then
	for _, desc in ipairs(playerGui:GetDescendants()) do registerTextElement(desc) end
	descAddedConn = playerGui.DescendantAdded:Connect(registerTextElement)
	descRemovingConn = playerGui.DescendantRemoving:Connect(function(inst) trackedTextElements[inst] = nil end)
end

local function isElementVisible(guiObj)
	if not guiObj or not guiObj.Parent or not guiObj:IsA("GuiObject") then return false end
	if isOurOwnUI(guiObj) or not guiObj.Visible then return false end
	if guiObj.AbsoluteSize.X < 8 or guiObj.AbsoluteSize.Y < 8 then return false end
	local curr = guiObj.Parent
	while curr and curr ~= LocalPlayer do
		if curr:IsA("GuiObject") and not curr.Visible then return false
		elseif curr:IsA("ScreenGui") and not curr.Enabled then return false end
		curr = curr.Parent
	end
	return true
end

local function clickGuiElement(rawElement)
	if not isElementVisible(rawElement) then return false end
	local target = rawElement
	for _ = 1, 5 do
		if not target or target:IsA("ScreenGui") then break end
		if target:IsA("GuiButton") then break end
		target = target.Parent
	end
	if not target or not target:IsA("GuiObject") then target = rawElement end

	for _, obj in ipairs({ target, rawElement }) do
		if obj:IsA("GuiButton") then
			if type(firesignal) == "function" then
				pcall(function() firesignal(obj.MouseButton1Click) firesignal(obj.Activated) end)
			end
			if type(getconnections) == "function" then
				pcall(function()
					for _, c in ipairs(getconnections(obj.MouseButton1Click)) do pcall(function() c:Fire() end) end
					for _, c in ipairs(getconnections(obj.Activated)) do pcall(function() c:Fire() end) end
				end)
			end
		end
	end

	pcall(function()
		local pos = target.AbsolutePosition
		local size = target.AbsoluteSize
		local inset = GuiService:GetGuiInset()
		local clickX = math.floor(pos.X + (size.X * 0.5))
		local clickY = math.floor(pos.Y + (size.Y * 0.5) + inset.Y)
		VirtualInputManager:SendMouseMoveEvent(clickX, clickY, game)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
		task.wait(0.04)
		VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
	end)
	return true
end

local function normalizeText(str)
	local s = string.lower(tostring(str or ""))
	return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function findVisibleElementsByText(targets, exactOnly)
	local results = {}
	for desc in pairs(trackedTextElements) do
		if not desc.Parent then
			trackedTextElements[desc] = nil
		elseif isElementVisible(desc) then
			local txt = normalizeText(desc.Text)
			if #txt > 0 and #txt < 40 then
				for _, t in ipairs(targets) do
					local targetNorm = normalizeText(t)
					if txt == targetNorm or (not exactOnly and string.find(txt, targetNorm, 1, true)) then
						table.insert(results, desc)
						break
					end
				end
			end
		end
	end
	return results
end

local function selectDesiredTimeMode()
	local num = string.match(normalizeTimeMode(Settings.TimeMode), "%d+") or "1"
	local validPatterns = {
		[num .. "min"] = true, [num .. "mins"] = true, [num .. "m"] = true, [num .. ":00"] = true
	}
	for desc in pairs(trackedTextElements) do
		if desc.Parent and isElementVisible(desc) then
			local compact = string.gsub(normalizeText(desc.Text), "%s+", "")
			if validPatterns[compact] then
				clickGuiElement(desc)
				task.wait(0.1)
			end
		end
	end
end

-- Periodic Fresh GC Scanner so a new match / Rematch never gets stuck on an old cached closure!
local cachedCurrentFn = nil
local lastGcScanTime  = 0

local function isValidActiveGameObj(obj)
	if type(obj) ~= "table" then return false end
	local st = rawget(obj, "state")
	if type(st) ~= "table" or type(rawget(st, "board")) ~= "table" then return false end
	if rawget(obj, "ended") == true or rawget(st, "ended") == true or rawget(obj, "gameOver") == true or rawget(st, "gameOver") == true then
		return false
	end
	if rawget(obj, "winner") ~= nil or rawget(st, "winner") ~= nil or rawget(st, "result") ~= nil then
		return false
	end
	return true
end

local function getActiveMatchObj(forceRescan)
	local now = os.clock()
	if not forceRescan and cachedCurrentFn and (now - lastGcScanTime) < 1.0 then
		local ok, obj = pcall(cachedCurrentFn)
		if ok and isValidActiveGameObj(obj) then
			return obj
		end
		cachedCurrentFn = nil
	end

	lastGcScanTime = now

	if type(filtergc) == "function" then
		local ok, found = pcall(function() return filtergc("function", { Name = "current" }) end)
		if ok and type(found) == "table" then
			for i = #found, 1, -1 do
				local fn = found[i]
				local s, obj = pcall(fn)
				if s and isValidActiveGameObj(obj) then
					cachedCurrentFn = fn
					return obj
				end
			end
		end
	end

	if type(getgc) == "function" then
		local ok, gcList = pcall(getgc, true)
		if ok and type(gcList) == "table" then
			for i = #gcList, 1, -1 do
				local v = gcList[i]
				if isValidActiveGameObj(v) and v.state.board[64] ~= nil then
					return v
				end
			end
		end
	end

	return nil
end

-- Strict Post-Game Modal check (only exact button texts "rematch", "new game", "game review" so chat/usernames never trigger false positives!)
local function isPostGameModalVisible()
	local postBtns = findVisibleElementsByText({ "rematch", "new game", "game review" }, true)
	return #postBtns > 0
end

local function matchesLocalPlayer(val)
	if not val then return false end
	if val == LocalPlayer or val == LocalPlayer.Name or val == LocalPlayer.DisplayName or val == LocalPlayer.UserId or val == tostring(LocalPlayer.UserId) then
		return true
	end
	if type(val) == "table" then
		local id = rawget(val, "UserId") or rawget(val, "userId") or rawget(val, "id")
		local nm = rawget(val, "Name") or rawget(val, "name") or rawget(val, "username")
		local pl = rawget(val, "Player") or rawget(val, "player")
		if id == LocalPlayer.UserId or nm == LocalPlayer.Name or pl == LocalPlayer then
			return true
		end
	end
	return false
end

local lastOpponentInfo = { name = nil, userId = nil }

local function updateOpponentFromGameObj(gameObj)
	if type(gameObj) ~= "table" then return end
	for _, tbl in ipairs({ gameObj, gameObj.state }) do
		if type(tbl) == "table" then
			local w = rawget(tbl, "white") or rawget(tbl, "White") or rawget(tbl, "whitePlayer")
			local b = rawget(tbl, "black") or rawget(tbl, "Black") or rawget(tbl, "blackPlayer")
			for _, pVal in ipairs({ w, b }) do
				if pVal and not matchesLocalPlayer(pVal) then
					if typeof(pVal) == "Instance" and pVal:IsA("Player") then
						lastOpponentInfo.name   = pVal.Name
						lastOpponentInfo.userId = pVal.UserId
						return
					elseif type(pVal) == "string" and #pVal > 1 and pVal ~= LocalPlayer.Name then
						lastOpponentInfo.name = pVal
						return
					elseif type(pVal) == "number" and pVal ~= LocalPlayer.UserId then
						lastOpponentInfo.userId = pVal
						return
					elseif type(pVal) == "table" then
						local nm = rawget(pVal, "Name") or rawget(pVal, "name") or rawget(pVal, "username")
						local id = rawget(pVal, "UserId") or rawget(pVal, "userId") or rawget(pVal, "id")
						if nm and nm ~= LocalPlayer.Name then lastOpponentInfo.name = nm end
						if id and id ~= LocalPlayer.UserId then lastOpponentInfo.userId = id end
					end
				end
			end
		end
	end
end

local function hasOpponentLeftOrDeclined()
	local declinedMsgs = findVisibleElementsByText({
		"declined", "opponent left", "player left", "disconnected",
		"left the game", "rematch declined", "unavailable", "cancelled", "canceled"
	}, false)
	if #declinedMsgs > 0 then return true end

	if lastOpponentInfo.userId or lastOpponentInfo.name then
		local stillInServer = false
		for _, p in ipairs(Players:GetPlayers()) do
			if (lastOpponentInfo.userId and p.UserId == lastOpponentInfo.userId)
				or (lastOpponentInfo.name and string.lower(p.Name) == string.lower(lastOpponentInfo.name))
			then
				stillInServer = true
				break
			end
		end
		if not stillInServer then return true end
	end
	return false
end

local postGamePhase = {
	rematchClickedAt = 0,
	newGameLastClick = 0,
}

local function resetPostGamePhase()
	postGamePhase.rematchClickedAt = 0
	postGamePhase.newGameLastClick = 0
end

local lastQueueAction = 0
local function executeLobbyOrPostGameClick(screenState)
	local now = os.clock()

	if screenState == "POSTGAME" then
		local rematchBtns = findVisibleElementsByText({ "rematch" }, true)
		local opponentGone = hasOpponentLeftOrDeclined()

		if postGamePhase.rematchClickedAt == 0 and not opponentGone and #rematchBtns > 0 then
			postGamePhase.rematchClickedAt = now
			for _, el in ipairs(rematchBtns) do
				clickGuiElement(el)
				task.wait(0.12)
			end
			return
		end

		local waitedSec = (postGamePhase.rematchClickedAt > 0) and (now - postGamePhase.rematchClickedAt) or 999
		if not opponentGone and waitedSec < 10.0 and #rematchBtns > 0 then
			return
		end

		if (now - postGamePhase.newGameLastClick) < 2.5 then return end
		postGamePhase.newGameLastClick = now

		selectDesiredTimeMode()
		task.wait(0.20)
		local newGameTargets = findVisibleElementsByText({ "new game", "play again", "play now" }, false)
		for _, el in ipairs(newGameTargets) do
			clickGuiElement(el)
			task.wait(0.12)
		end

	elseif screenState == "LOBBY" then
		if (now - lastQueueAction) < 2.8 then return end
		lastQueueAction = now
		resetPostGamePhase()
		selectDesiredTimeMode()
		task.wait(0.20)
		local playNowTargets = findVisibleElementsByText({ "play now" }, true)
		for _, el in ipairs(playNowTargets) do
			clickGuiElement(el)
			task.wait(0.12)
		end
	end
end

local function getBoardSignature(State)
	local parts = table.create(66)
	parts[1] = tostring(State.turn)
	parts[2] = tostring(State.full or 0)
	for i = 1, 64 do parts[i + 2] = tostring(State.board[i] or 0) end
	return table.concat(parts, ",")
end

local function getMyColor(gameObj)
	for _, tbl in ipairs({ gameObj, gameObj.state }) do
		if type(tbl) == "table" then
			for _, key in ipairs({ "color", "side", "myColor", "playerColor", "localColor", "team" }) do
				local v = rawget(tbl, key)
				if v == 1 or v == -1 then return v end
				if v == "w" or v == "white" or v == "White" then return 1 end
				if v == "b" or v == "black" or v == "Black" then return -1 end
			end
			local w = rawget(tbl, "white") or rawget(tbl, "White") or rawget(tbl, "whitePlayer")
			local b = rawget(tbl, "black") or rawget(tbl, "Black") or rawget(tbl, "blackPlayer")
			if matchesLocalPlayer(w) then return 1 end
			if matchesLocalPlayer(b) then return -1 end
		end
	end

	-- Visual Fallback: check rank '1' vs '8' Y-coordinate on screen
	local y1, y8 = nil, nil
	for desc in pairs(trackedTextElements) do
		if desc.Parent and isElementVisible(desc) then
			local t = string.gsub(desc.Text or "", "%s+", "")
			if t == "1" then y1 = desc.AbsolutePosition.Y
			elseif t == "8" then y8 = desc.AbsolutePosition.Y end
		end
	end
	if y1 and y8 then
		return (y1 > y8) and 1 or -1
	end
	return nil
end

local function isMyTurnNow(State, myColor)
	if not myColor then return true end
	local t = State.turn
	if t == myColor then return true end
	if myColor == 1 and (t == "w" or t == "white" or t == "White" or t == 0 or t == true) then return true end
	if myColor == -1 and (t == "b" or t == "black" or t == "Black" or t == 2 or t == false) then return true end
	return false
end

local function detectMyClockSeconds(gameObj, myColor)
	if type(gameObj) == "table" then
		local st = rawget(gameObj, "state")
		for _, tbl in ipairs({ st, gameObj }) do
			if type(tbl) == "table" then
				local clocks = rawget(tbl, "clocks") or rawget(tbl, "timers") or rawget(tbl, "time") or rawget(tbl, "remainingTime")
				if type(clocks) == "table" and myColor then
					local cVal = clocks[myColor] or (myColor == 1 and (clocks.w or clocks.W or clocks.white or clocks[1])) or (myColor == -1 and (clocks.b or clocks.B or clocks.black or clocks[2]))
					if type(cVal) == "number" and cVal > 0 and cVal <= 3600 then
						return cVal
					end
				end
			end
		end
	end

	if playerGui then
		local bestX = -1
		local foundSec = nil
		for desc in pairs(trackedTextElements) do
			if desc.Parent and isElementVisible(desc) then
				local m, s = string.match(desc.Text or "", "^%s*(%d+):(%d+%.?%d*)%s*$")
				if m and s then
					local sec = tonumber(m) * 60 + tonumber(s)
					if sec and sec > 0 and sec <= 3600 and desc.AbsolutePosition.X > bestX then
						bestX = desc.AbsolutePosition.X
						foundSec = sec
					end
				end
			end
		end
		if foundSec then return foundSec end
	end

	local map = { ["1 min"] = 60, ["3 min"] = 180, ["10 min"] = 600 }
	return map[Settings.TimeMode] or 60
end

local myMovesInCurrentMatch = 0

local function computeHumanThinkDelay(remSec, moveInfo, thinkElapsedSec)
	if not Settings.HumanPace then return 0 end
	if not moveInfo then return 0 end

	local mode = normalizeTimeMode(Settings.TimeMode)
	local panicThreshold = (mode == "1 min") and 11.0 or 15.0
	if remSec <= panicThreshold then
		return 0
	end

	if moveInfo.isForced then
		if remSec <= 20.0 then return 0 end
		local forcedPause = (mode == "10 min") and (0.85 + math.random() * 0.75)
			or ((mode == "3 min") and (0.55 + math.random() * 0.55) or (0.38 + math.random() * 0.35))
		return math.max(0, forcedPause - thinkElapsedSec)
	end

	local moveNum    = math.max(tonumber(moveInfo.moveNum) or 1, myMovesInCurrentMatch + 1)
	local isBook     = (moveInfo.isBook == true)
	local complexity = tonumber(moveInfo.complexity) or 2

	local isDeepTankTurn = (moveNum >= 5 and math.random() < 0.28)
	if isDeepTankTurn then
		complexity = math.max(complexity, 3)
	end

	if isBook or moveNum <= 4 then
		local openWait
		if mode == "10 min" or remSec > 200 then
			openWait = 1.40 + math.random() * 1.80
		elseif mode == "3 min" or remSec > 70 then
			openWait = 0.95 + math.random() * 1.25
		else
			openWait = 0.65 + math.random() * 0.75
		end
		return math.max(0, openWait - thinkElapsedSec)
	end

	local targetTotal = 0

	if remSec > 210 or (mode == "10 min" and remSec > 120) then
		if isDeepTankTurn then
			targetTotal = 9.50 + math.random() * 9.50
		elseif complexity >= 3 then
			targetTotal = 5.50 + math.random() * 5.50
		elseif complexity == 2 then
			targetTotal = 3.20 + math.random() * 3.30
		else
			targetTotal = 1.50 + math.random() * 1.40
		end

	elseif remSec > 65 or (mode == "3 min" and remSec > 42) then
		if isDeepTankTurn and remSec > 85 then
			targetTotal = 5.20 + math.random() * 4.80
		elseif complexity >= 3 then
			targetTotal = 3.10 + math.random() * 2.90
		elseif complexity == 2 then
			targetTotal = 1.80 + math.random() * 1.80
		else
			targetTotal = 0.90 + math.random() * 0.85
		end

	elseif remSec > 30 then
		if isDeepTankTurn then
			targetTotal = 2.60 + math.random() * 1.65
		elseif complexity >= 3 then
			targetTotal = 1.85 + math.random() * 1.35
		elseif complexity == 2 then
			targetTotal = 1.25 + math.random() * 1.05
		else
			targetTotal = 0.65 + math.random() * 0.55
		end

	elseif remSec > 18 then
		if complexity >= 3 then
			targetTotal = 0.95 + math.random() * 0.75
		elseif complexity == 2 then
			targetTotal = 0.60 + math.random() * 0.55
		else
			targetTotal = 0.35 + math.random() * 0.30
		end

	else
		targetTotal = 0.18 + math.random() * 0.25
	end

	local safeMaxWait = math.max(0.2, (remSec - panicThreshold) * 0.22)
	targetTotal = math.min(targetTotal, safeMaxWait)

	return math.max(0, targetTotal - thinkElapsedSec)
end

local function sendMove(bestMove)
	pcall(function()
		PlayMove:FireServer("move", {
			from  = bestMove.from,
			to    = bestMove.to,
			promo = bestMove.promo or 0,
		})
	end)
end

if Window then
	local MainTab = Window:CreateTab("Auto Bot", 10886548710)
	local ControlSection = MainTab:CreateSection("Sill Solo 2800+ (Stockfish Brain)")

	ControlSection:CreateToggle({
		Name = "🤖 เดินหมากอัตโนมัติ (Auto Play 100%)",
		Description = "สมองกล Stockfish Architecture + ระบบกันค้างกลางเกม (Anti-Freeze Watchdog)",
		CurrentValue = Settings.AutoPlay,
		Callback = function(Value)
			Settings.AutoPlay = Value
			saveSettings()
		end
	})

	ControlSection:CreateToggle({
		Name = "🎭 จังหวะคิดเนียนตามเวลาจริง (Smart Human Pacing)",
		Description = "เผาเวลาตามโหมด 1m / 3m / 10m อย่างสมจริง และเร่งสปีดเมื่อเวลาใกล้หมด",
		CurrentValue = Settings.HumanPace,
		Callback = function(Value)
			Settings.HumanPace = Value
			saveSettings()
		end
	})

	ControlSection:CreateToggle({
		Name = "🔄 จบเกมกด Rematch (รอ 10 วิ) -> New Game อัตโนมัติ",
		Description = "จบเกมกด Rematch ก่อน รอ 10 วิ (หรือถ้าคู่แข่งออก/ปฏิเสธ จะกด New Game ทันที)",
		CurrentValue = Settings.AutoQueue,
		Callback = function(Value)
			Settings.AutoQueue = Value
			saveSettings()
		end
	})

	ControlSection:CreateDropdown({
		Name = "⏱️ โหมดเวลาที่จะกดหาห้อง (Time Mode)",
		Description = "รองรับ 1 min, 3 min, 10 min",
		Options = { "1 min", "3 min", "10 min" },
		CurrentOption = Settings.TimeMode,
		Callback = function(Option)
			local rawOpt = type(Option) == "table" and Option[1] or Option
			Settings.TimeMode = normalizeTimeMode(rawOpt)
			saveSettings()
			task.spawn(selectDesiredTimeMode)
		end
	})
end

local running = true

ENV.__SillSoloCleanup = function()
	running = false
	if teleportConn then pcall(function() teleportConn:Disconnect() end) end
	if descAddedConn then pcall(function() descAddedConn:Disconnect() end) end
	if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) end
	if SilL and SilL.Destroy then pcall(function() SilL:Destroy() end) end
	if createdScreenGui then pcall(function() createdScreenGui:Destroy() end) end
end

ENV.SillChessBotCleanup = function()
	purgeLegacyUIs()
end
_G.SillChessBotCleanup = ENV.SillChessBotCleanup

--==============================================================================
-- 8. MAIN LOOP WITH NEVER-STUCK WATCHDOG & AUTOMATIC FALLBACK RECOVERY
--==============================================================================
task.spawn(function()
	local lastHandledSig = ""
	local lastAttemptTime = 0
	local retryCount = 0

	while running do
		purgeLegacyUIs()

		local postGameModal = isPostGameModalVisible()
		local gameObj = not postGameModal and getActiveMatchObj(retryCount >= 2) or nil
		local State   = gameObj and gameObj.state

		if State and State.board and not postGameModal then
			resetPostGamePhase()
			updateOpponentFromGameObj(gameObj)

			if Settings.AutoPlay then
				local myColor = getMyColor(gameObj)
				if isMyTurnNow(State, myColor) then
					local currentSig = getBoardSignature(State)
					if currentSig ~= lastHandledSig then
						retryCount = 0
					end

					-- Never lock out! Retry every 0.70s if the server didn't register the move yet
					local shouldAct = (currentSig ~= lastHandledSig) or ((os.clock() - lastAttemptTime) > 0.70)

					if shouldAct then
						local turnStart = os.clock()
						local remSec    = detectMyClockSeconds(gameObj, myColor)
						local ok, bestMove

						-- Tiered Recovery Watchdog:
						-- Attempt 0 & 1: Use our primary 2800+ Stockfish Engine move
						-- Attempt 2+: If server rejected primary move (e.g. special castling/promo state), try game's built-in Bot module or our 2nd best legal move!
						if retryCount >= 2 then
							local backupMv = computeBackupMoveFromGameModule(State)
							if backupMv then
								ok, bestMove = true, backupMv
							else
								ok, bestMove = pcall(computeBestMove, State, math.min(remSec, 10))
								if ok and bestMove and bestMove.altMove and (retryCount % 2 == 1) then
									bestMove = bestMove.altMove
								end
							end
						else
							ok, bestMove = pcall(computeBestMove, State, remSec)
						end

						local thinkElapsed = os.clock() - turnStart

						-- Human Pacing only on the first attempt of a turn (retryCount == 0)
						if ok and bestMove and retryCount == 0 and Settings.HumanPace then
							local extraWait = computeHumanThinkDelay(remSec, bestMove, thinkElapsed)
							if extraWait > 0.02 then
								local mode = normalizeTimeMode(Settings.TimeMode)
								local panicCut = (mode == "1 min") and 11.0 or 15.0
								local waitUntil = os.clock() + extraWait
								while os.clock() < waitUntil do
									if not running or not Settings.AutoPlay or isPostGameModalVisible() then break end
									local liveRem = detectMyClockSeconds(gameObj, myColor)
									if liveRem <= panicCut then break end
									local checkObj = getActiveMatchObj(false)
									local checkSt  = checkObj and checkObj.state
									if not checkSt or getBoardSignature(checkSt) ~= currentSig then break end
									task.wait(0.03)
								end
							end
						end

						local latestObj   = getActiveMatchObj(false)
						local latestState = latestObj and latestObj.state
						if ok and bestMove and running and Settings.AutoPlay and latestState and getBoardSignature(latestState) == currentSig then
							sendMove(bestMove)
							if retryCount == 0 then
								myMovesInCurrentMatch = myMovesInCurrentMatch + 1
							end
							lastHandledSig  = currentSig
							lastAttemptTime = os.clock()
							retryCount      = retryCount + 1
						end
					end
				end
			end
			task.wait(0.03)
		else
			lastHandledSig        = ""
			retryCount            = 0
			myMovesInCurrentMatch = 0
			cachedCurrentFn       = nil
			if postGameModal then
				if Settings.AutoQueue then
					executeLobbyOrPostGameClick("POSTGAME")
				end
			elseif #findVisibleElementsByText({ "play now" }, true) > 0 then
				if Settings.AutoQueue then
					executeLobbyOrPostGameClick("LOBBY")
				end
			end
			task.wait(0.35)
		end
	end
end)

]===]

if type(writefile) == "function" then
	local fullSelfInstaller = "local __SOLO_2800_PAYLOAD = [===[" .. __SOLO_2800_PAYLOAD .. "]===]\n"
		.. "if type(writefile) == 'function' then pcall(writefile, 'SillChessBot_AutoExec.lua', __SOLO_2800_PAYLOAD) pcall(writefile, 'SillChessBot_AutoLoader.lua', __SOLO_2800_PAYLOAD) end\n"
		.. "return loadstring(__SOLO_2800_PAYLOAD)()"
	pcall(writefile, "SillChessBot_AutoExec.lua", fullSelfInstaller)
	pcall(writefile, "SillChessBot_AutoLoader.lua", fullSelfInstaller)
end

return loadstring(__SOLO_2800_PAYLOAD)()
