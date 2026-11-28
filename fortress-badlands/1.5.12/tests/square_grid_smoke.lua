package.path='./?.lua;'..package.path
local r=require('rules')
assert(r.ROWS==11 and r.COLS==7)
local widths={3,4,5,6,7,6,7,6,5,4,3}
local n=0
for row=0,10 do
 assert(r.rowWidths[row+1]==widths[row+1])
 for col=0,6 do
  local a=r.playable(row,col)
  assert(a==(col<widths[row+1]))
  assert(a==r.playable(10-row,col))
  if a then n=n+1 end
 end
end
assert(n==56)
local s=r.new(108)
for _,u in ipairs(s.units)do assert(r.playable(u.r,u.c)) end
assert(r.playable(0,1) and not r.playable(0,3))
assert(r.playable(5,5) and not r.playable(5,6))
assert(r.playable(6,6) and not r.playable(7,6))
print('PASS: 11x7, 56-hex symmetric hourglass mask with no phantom cells')
