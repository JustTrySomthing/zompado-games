-- Presentation commands occupy host turns but never enter rules.replay or its RNG.
-- The spectator returns each attack/reward slot automatically. The attacker
-- releases the next gameplay turn by confirming the result.
local flow={}
function flow.parse(raw,start)
  local actions,phase={},nil
  for i=start,#raw do
    local token=raw[i]
    if phase then
      if (phase=='attack' or phase=='reward') and token=='K' then
        phase=phase=='attack' and 'result' or 'healed'
      elseif phase=='result' and token=='R' then phase='reward'
      elseif (phase=='result' or phase=='healed') and token=='C' then phase=nil
      else return nil,'Invalid battle handoff.' end
    else
      actions[#actions+1]=token
      if token:match('^[AD]%d') then phase='attack' end
    end
  end
  return actions,phase
end
return flow
