-- Lua Fighting game sample script
--
-- README:
--
-- Structure of this script:
--	
--	**) Character "class"	- holds all character specific information, like hitboxes, moves, state machine, and Update(), Input() functions
--	***) ResolveCharacters() function	- updates the two players and checks for collision, moves the camera, etc.
--	****) Main loop process	- initialize script and do call update() in an infinite loop
--
--
-- The script is programmable using common fighting game "numpad notations" (read this if you are unfamiliar: http://www.dustloop.com/wiki/index.php/Notation )
-- There are four action buttons: A, B, C, D
--	So for example a forward motion combined with action D would look like this in code: "6D" 
--	A D action without motion (neutral D) would be: "5D"
--	A quarter circle forward + A would be "236A"
--	"Shoryuken" + A command would be: "623A"
--	For a full circle motion, the input would be: "23698741"
--		But because that full circle motion is difficult to execute properly, we can make it easier by accpeting similar inputs, like:
--			"2684" or "2369874"...
--	The require_input("inputstring") facility will help detect instant input execution
--	The require_input_window("inputstring", allowed_latency_window) facility can detect inputs that are executed over multiple frames
--	Neutral motion is "5", that is not necessary to put into input strings in most cases, but it can help, for example: double tap right button would need a neutral in between the two presses, like this: 656

local scene = GetScene()

-- **The character "class" is a wrapper function that returns a local internal table called "self"
local function Character(face, shirt_color)
	local self = {
		model = INVALID_ENTITY,
		effect_dust = INVALID_ENTITY,
		effect_hit = INVALID_ENTITY,
		face = 1, -- face direction (X)
		request_face = 1,
		position = Vector(),
		velocity = Vector(),
		force = Vector(),
		frame = 0,
		input_buffer = {},
		clipbox = AABB(),
		hurtboxes = {},
		hitboxes = {},
		hitconfirm = false,
		hurt = false,
		jumps_remaining = 2,
		opponent_force = Vector(),

		-- Effect helpers:
		spawn_effect_hit = function(self, local_pos)
			scene.Component_GetEmitter(self.effect_hit).Burst(50)
			local transform_component = scene.Component_GetTransform(self.effect_hit)
			transform_component.ClearTransform()
			transform_component.Translate(vector.Add(self.position, local_pos))
		end,
		spawn_effect_dust = function(self, local_pos)
			local emitter_component = scene.Component_GetEmitter(self.effect_dust).Burst(10)
			local transform_component = scene.Component_GetTransform(self.effect_dust)
			transform_component.ClearTransform()
			transform_component.Translate(self.position)
		end,

		-- Common requirement conditions for state transitions:
		require_input_window = function(self, inputString, window) -- player input notation with some tolerance to input execution window (in frames) (help: see readme on top of this file)
			-- reduce remaining input with non-expired commands:
			for i,element in ipairs(self.input_buffer) do
				if(element.age <= window and element.command == string.sub(inputString, 0, string.len(element.command))) then
					inputString = string.sub(inputString, string.len(element.command) + 1)
					if(inputString == "") then
						return true
					end
				end
			end
			return false -- match failure
		end,
		require_input = function(self, inputString) -- player input notation (immediate) (help: see readme on top of this file)
			return self:require_input_window(inputString, 0)
		end,
		require_frame = function(self, frame) -- specific frame
			return self.frame == frame
		end,
		require_window = function(self, frameStart,  frameEnd) -- frame window range
			return self.frame >= frameStart and self.frame <= frameEnd
		end,
		require_animationfinish = function(self) -- animation is finished
			return scene.Component_GetAnimation(self.states[self.state].anim).IsEnded()
		end,
		require_hitconfirm = function(self) -- true if this player successfully hit the other
			return self.hitconfirm
		end,
		require_hurt = function(self) -- true if this player was hit by the other
			return self.hurt
		end,
		
		-- Common motion helpers:
		require_motion_qcf = function(self, button)
			local window = 20
			return 
				self:require_input_window("236" .. button, window) or
				self:require_input_window("26" .. button, window)
		end,
		require_motion_shoryuken = function(self, button)
			local window = 20
			return 
				self:require_input_window("623" .. button, window) or
				self:require_input_window("626" .. button, window)
		end,

		-- List all possible states:
		states = {
			-- Common states:
			Idle = {
				anim_name = "Idle",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.jumps_remaining = 2
				end,
			},
			Walk_Backward = {
				anim_name = "Back",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(-0.025 * self.face, 0))
				end,
			},
			Walk_Forward = {
				anim_name = "Forward",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(0.025 * self.face, 0))
				end,
			},
			Dash_Backward = {
				anim_name = "BDash",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(0,2)) then
						self.force = vector.Add(self.force, Vector(-0.07 * self.face, 0.1))
					end
					if(self:require_frame(14)) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			RunStart = {
				anim_name = "RunStart",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
			},
			Run = {
				anim_name = "Run",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(0.08 * self.face, 0))
					if(self.frame % 15 == 0) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			RunEnd = {
				anim_name = "RunEnd",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
			},
			Jump = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(0, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			JumpBack = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(-0.2 * self.face, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			JumpForward = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(0.2 * self.face, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			FallStart = {
				anim_name = "FallStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Fall = {
				anim_name = "Fall",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			FallEnd = {
				anim_name = "FallEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_frame(2)) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			CrouchStart = {
				anim_name = "CrouchStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
			},
			Crouch = {
				anim_name = "Crouch",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
			},
			CrouchEnd = {
				anim_name = "CrouchEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Turn = {
				anim_name = "Turn",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.face = self.request_face
					end
				end,
			},
			
			-- Attack states:
			LightPunch = {
				anim_name = "LightPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3,5)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
					end
				end,
			},
			ForwardLightPunch = {
				anim_name = "FLightPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(12,14)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3.5,6)) )
						self.opponent_force = Vector(0.01 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
					end
				end,
			},
			HeavyPunch = {
				anim_name = "HeavyPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3.5,5)) )
						self.opponent_force = Vector(0.08 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
					end
				end,
			},
			LowPunch = {
				anim_name = "LowPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
				update = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,0), Vector(2.8,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,2,-1))
					end
				end,
			},
			LightKick = {
				anim_name = "LightKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
					end
				end,
			},
			HeavyKick = {
				anim_name = "HeavyKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(8,13)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(4,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.6 * self.face,1.4,-1))
					end
				end,
			},
			AirKick = {
				anim_name = "AirKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
					end
				end,
			},
			AirHeavyKick = {
				anim_name = "AirHeavyKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
					end
				end,
			},
			LowKick = {
				anim_name = "LowKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
				update = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,0), Vector(3,3)) )
						self.opponent_force = Vector(0.04 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,1,-1))
					end
				end,
			},
			Uppercut = {
				anim_name = "Uppercut",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(3,5)) then
						table.insert(self.hitboxes, AABB(Vector(0,3), Vector(2.3,7)) )
						self.opponent_force = Vector(0.04 * self.face, 0.4)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
					end
				end,
			},
			SpearJaunt = {
				anim_name = "SpearJaunt",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1.5), Vector(1.5, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_frame(16)) then
						self.force = vector.Add(self.force, Vector(1.3 * self.face))
					end
					if(self:require_window(17,40)) then
						table.insert(self.hitboxes, AABB(Vector(0,1), Vector(4.5,5)) )
						self.opponent_force = Vector(0.08 * self.face)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(3 * self.face,3.6,-1))
					end
				end,
			},
			Shoryuken = {
				anim_name = "Shoryuken",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_frame(0)) then
						self.force = vector.Add(self.force, Vector(0.3 * self.face, 0.9))
					end
					if(self:require_window(2,20)) then
						table.insert(self.hitboxes, AABB(Vector(0,2), Vector(2.3,7)) )
					end
					if(self:require_window(2,8)) then
						self.opponent_force = Vector(0, 1)
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
					end
				end,
			},
			
			-- Hurt states:
			StaggerStart = {
				anim_name = "StaggerStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Stagger = {
				anim_name = "Stagger",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerEnd = {
				anim_name = "StaggerEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},

			StaggerCrouchStart = {
				anim_name = "StaggerCrouchStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerCrouch = {
				anim_name = "StaggerCrouch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerCrouchEnd = {
				anim_name = "StaggerCrouchEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},

			StaggerAirStart = {
				anim_name = "StaggerAirStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerAir = {
				anim_name = "StaggerAir",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerAirEnd = {
				anim_name = "StaggerAirEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.position.GetY() < 1 and self.velocity.GetY() < 0) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			
			Downed = {
				anim_name = "Downed",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 1)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 1)),
			},
			Getup = {
				anim_name = "Getup",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
		},

		-- State machine describes all possible state transitions (item order is priority high->low):
		--	StateFrom = {
		--		{ "StateTo1", condition = function(self) return [requirements that should be met] end },
		--		{ "StateTo2", condition = function(self) return [requirements that should be met] end },
		--	}
		statemachine = {
			Idle = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "SpearJaunt", condition = function(self) return self:require_motion_qcf("D") end, },
				{ "Turn", condition = function(self) return self.request_face ~= self.face end, },
				{ "Walk_Forward", condition = function(self) return self:require_input("6") end, },
				{ "Walk_Backward", condition = function(self) return self:require_input("4") end, },
				{ "Jump", condition = function(self) return self:require_input("8") end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
			},
			Walk_Backward = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "Walk_Forward", condition = function(self) return self:require_input("6") end, },
				{ "Dash_Backward", condition = function(self) return self:require_input_window("454", 7) end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
				{ "ForwardLightPunch", condition = function(self) return self:require_input("6A") end, },
				{ "HeavyKick", condition = function(self) return self:require_input("6C") end, },
			},
			Walk_Forward = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "SpearJaunt", condition = function(self) return self:require_motion_qcf("D") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "Walk_Backward", condition = function(self) return self:require_input("4") end, },
				{ "RunStart", condition = function(self) return self:require_input_window("656", 7) end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
				{ "ForwardLightPunch", condition = function(self) return self:require_input("6A") end, },
				{ "HeavyKick", condition = function(self) return self:require_input("6C") end, },
			},
			Dash_Backward = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			RunStart = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Run", condition = function(self) return self:require_animationfinish() end, },
			},
			Run = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Jump", condition = function(self) return self:require_input("8") end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "RunEnd", condition = function(self) return not self:require_input("6") end, },
			},
			RunEnd = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Jump = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			JumpForward = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			JumpBack = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			FallStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "FallEnd", condition = function(self) return self.position.GetY() <= 0.5 end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
			},
			Fall = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Jump", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("58", 7) end, },
				{ "JumpBack", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("57", 7) end, },
				{ "JumpForward", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("59", 7) end, },
				{ "FallEnd", condition = function(self) return self.position.GetY() <= 0.5 end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
			},
			FallEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self.position.GetY() <= 0 and self:require_animationfinish() end, },
			},
			CrouchStart = { 
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "Crouch", condition = function(self) return (self:require_input("1") or self:require_input("2") or self:require_input("3")) and self:require_animationfinish() end, },
			},
			Crouch = { 
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "CrouchEnd", condition = function(self) return self:require_input("5") or self:require_input("4") or self:require_input("6") or self:require_input("7") or self:require_input("8") or self:require_input("9") end, },
				{ "LowPunch", condition = function(self) return self:require_input("2A") or self:require_input("1A") or self:require_input("3A") end, },
				{ "LowKick", condition = function(self) return self:require_input("2C") or self:require_input("1C") or self:require_input("3C") end, },
				{ "Uppercut", condition = function(self) return self:require_input("2B") or self:require_input("1B") or self:require_input("3B") end, },
			},
			CrouchEnd = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Turn = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			LightPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			ForwardLightPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			HeavyPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			LowPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			LightKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			HeavyKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			AirKick = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
			},
			AirHeavyKick = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
			},
			LowKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			Uppercut = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			SpearJaunt = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Shoryuken = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "FallStart", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Stagger", condition = function(self) return self:require_animationfinish() end, },
			},
			Stagger = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerCrouchStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerCrouch", condition = function(self) return self:require_animationfinish() end, },
			},
			StaggerCrouch = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerCrouchEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerCrouchEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerAirStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerAir", condition = function(self) return self:require_animationfinish() end, },
			},
			StaggerAir = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerAirEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerAirEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Downed", condition = function(self) return self:require_animationfinish() and self.position.GetY() < 0.2 end, },
			},

			Downed = { 
				{ "Getup", condition = function(self) return self:require_input("A") or self:require_input("B") or self:require_input("C") or self.frame > 60 end, },
			},
			Getup = { 
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
		},

		state = "Idle", -- starting state

	
		-- Ends the current state:
		EndState = function(self)
			scene.Component_GetAnimation(self.states[self.state].anim).Stop()
		end,
		-- Starts a new state:
		StartState = function(self, dst_state)
			scene.Component_GetAnimation(self.states[dst_state].anim).Play()
			self.frame = 0
			self.state = dst_state
		end,
		-- Parse state machine at current state and perform transition if applicable:
		StepStateMachine = function(self)
			local transition_candidates = self.statemachine[self.state]
			if(transition_candidates ~= nil) then
				for i,dst in pairs(transition_candidates) do
					-- check transition requirement conditions:
					local requirements_met = true
					if(dst.condition ~= nil) then
						requirements_met = dst.condition(self)
					end
					if(requirements_met) then
						-- transition to new state when all requirements are met:
						self:EndState()
						self:StartState(dst[1])
						return
					end
				end
			end
		end,
		-- Execute the currently active state:
		ExecuteCurrentState = function(self)

			self.clipbox = AABB()
			self.hurtboxes = {}
			self.hitboxes = {}

			local current_state = self.states[self.state]
			if(current_state ~= nil) then
				if(current_state.update ~= nil) then
					current_state.update(self)
				end
				if(current_state.clipbox ~= nil) then
					self.clipbox = current_state.clipbox
				end
				if(current_state.hurtbox ~= nil) then
					table.insert(self.hurtboxes, current_state.hurtbox)
				end
			end
		end,
	

		Create = function(self, face, shirt_color)

			-- Load the model into a custom scene:
			--	We use a custom scene because if two models are loaded into the global scene, they will have name collisions
			--	and thus we couldn't properly query entities by name
			local model_scene = Scene()
			self.model = LoadModel(model_scene, "../models/havoc/havoc.wiscene")

			-- Place model according to starting facing direction:
			self.face = face
			self.request_face = face
			self.position = Vector(self.face * -4)

			-- Set shirt color todifferentiate between characters:
			local shirt_material_entity = model_scene.Entity_FindByName("material_shirt")
			model_scene.Component_GetMaterial(shirt_material_entity).SetBaseColor(shirt_color)
		
			-- Initialize states:
			for i,state in pairs(self.states) do
				state.anim = model_scene.Entity_FindByName(state.anim_name)
				if(state.looped ~= nil) then
					model_scene.Component_GetAnimation(state.anim).SetLooped(state.looped)
				end
			end

			-- Move the custom scene into the global scene:
			scene.Merge(model_scene)



			-- Load effects:
			local effect_scene = Scene()
			
			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_dust.wiscene")
			self.effect_dust = effect_scene.Entity_FindByName("dust")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_dust).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)

			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_hiteffect.wiscene")
			self.effect_hit = effect_scene.Entity_FindByName("hit")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_hit).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)


			self:StartState(self.state)

		end,
	
		ai_state = "Idle",
		AI = function(self)
			-- todo some better AI bot behaviour
			if(self.ai_state == "Jump") then
				table.insert(self.input_buffer, {age = 0, command = "8"})
			elseif(self.ai_state == "Crouch") then
				table.insert(self.input_buffer, {age = 0, command = "2"})
			else
				table.insert(self.input_buffer, {age = 0, command = "5"})
			end
		end,

		Input = function(self)

			-- read input (todo gamepad/stick):
			local left = input.Down(string.byte('A'))
			local right = input.Down(string.byte('D'))
			local up = input.Down(string.byte('W'))
			local down = input.Down(string.byte('S'))
			local A = input.Press(VK_RIGHT)
			local B = input.Press(VK_UP)
			local C = input.Press(VK_LEFT)
			local D = input.Press(VK_DOWN)

			-- swap left and right if facing the opposite side:
			if(self.face < 0) then
				local tmp = right
				right = left
				left = tmp
			end

			if(up and left) then
				table.insert(self.input_buffer, {age = 0, command = "7"})
			elseif(up and right) then
				table.insert(self.input_buffer, {age = 0, command = "9"})
			elseif(up) then
				table.insert(self.input_buffer, {age = 0, command = "8"})
			elseif(down and left) then
				table.insert(self.input_buffer, {age = 0, command = "1"})
			elseif(down and right) then
				table.insert(self.input_buffer, {age = 0, command = "3"})
			elseif(down) then
				table.insert(self.input_buffer, {age = 0, command = "2"})
			elseif(left) then
				table.insert(self.input_buffer, {age = 0, command = "4"})
			elseif(right) then
				table.insert(self.input_buffer, {age = 0, command = "6"})
			else
				table.insert(self.input_buffer, {age = 0, command = "5"})
			end
			
			if(A) then
				table.insert(self.input_buffer, {age = 0, command = "A"})
			end
			if(B) then
				table.insert(self.input_buffer, {age = 0, command = "B"})
			end
			if(C) then
				table.insert(self.input_buffer, {age = 0, command = "C"})
			end
			if(D) then
				table.insert(self.input_buffer, {age = 0, command = "D"})
			end



		end,

		Update = function(self)
			self.frame = self.frame + 1

			self:StepStateMachine()
			self:ExecuteCurrentState()

			-- Manage input buffer:
			for i,element in pairs(self.input_buffer) do -- every input gets older by one frame
				element.age = element.age + 1
			end
			if(#self.input_buffer > 60) then -- only keep the last 60 inputs
				table.remove(self.input_buffer, 1)
			end
		
			-- force from gravity:
			self.force = vector.Add(self.force, Vector(0,-0.04,0))

			-- apply force:
			self.velocity = vector.Add(self.velocity, self.force)
			self.force = Vector()

			-- aerial drag:
			self.velocity = vector.Multiply(self.velocity, 0.98)
		
			-- apply velocity:
			self.position = vector.Add(self.position, self.velocity)
		
			-- check if we are below or on the ground:
			if(self.position.GetY() <= 0 and self.velocity.GetY()<=0) then
				self.position.SetY(0) -- snap to ground
				self.velocity.SetY(0) -- don't fall below ground
				self.velocity = vector.Multiply(self.velocity, 0.8) -- ground drag
			end
			
			-- Transform component gets set as absolute coordinates every frame:
			local model_transform = scene.Component_GetTransform(self.model)
			model_transform.ClearTransform()
			model_transform.Translate(self.position)
			model_transform.Rotate(Vector(0, math.pi * ((self.face - 1) * 0.5)))
			model_transform.UpdateTransform()

			-- Update hitboxes, etc:
			local model_mat = model_transform.GetMatrix()
			self.clipbox = self.clipbox.Transform(model_mat)
			for i,hitbox in ipairs(self.hitboxes) do
				self.hitboxes[i] = hitbox.Transform(model_mat)
				DrawBox(self.hitboxes[i].GetAsBoxMatrix(), Vector(1,0,0,1))
			end
			for i,hurtbox in ipairs(self.hurtboxes) do
				self.hurtboxes[i] = hurtbox.Transform(model_mat)
				DrawBox(self.hurtboxes[i].GetAsBoxMatrix(), Vector(0,1,0,1))
			end

			-- Some debug draw:
			DrawPoint(model_transform.GetPosition(), 0.1, Vector(1,0,0,1))
			DrawLine(model_transform.GetPosition(),model_transform.GetPosition():Add(self.velocity), Vector(0,1,0,10))
			DrawLine(vector.Add(model_transform.GetPosition(), Vector(0,1)),vector.Add(model_transform.GetPosition(), Vector(0,1)):Add(Vector(self.face)), Vector(0,0,1,1))
			DrawBox(self.clipbox.GetAsBoxMatrix(), Vector(1,1,0,1))
		
		end

	}

	self:Create(face, shirt_color)
	return self
end


-- script camera state:
local camera_position = Vector()
local camera_transform = TransformComponent()

-- ***Interaction between two characters:
local ResolveCharacters = function(player1, player2)
		
	player1:Input()
	player2:AI()

	player1:Update()
	player2:Update()

	-- Hit/Hurt:
	player1.hitconfirm = false
	player1.hurt = false
	player2.hitconfirm = false
	player2.hurt = false
	-- player1 hits player2:
	for i,hitbox in pairs(player1.hitboxes) do
		for j,hurtbox in pairs(player2.hurtboxes) do
			if(hitbox.Intersects2D(hurtbox)) then
				player1.hitconfirm = true
				player2.hurt = true
				player2.velocity = player1.opponent_force
				break
			end
		end
	end
	player1.opponent_force = Vector()
	-- player2 hits player1:
	for i,hitbox in ipairs(player2.hitboxes) do
		for j,hurtbox in ipairs(player1.hurtboxes) do
			if(hitbox.Intersects2D(hurtbox)) then
				player2.hitconfirm = true
				player1.hurt = true
				player1.velocity = player2.opponent_force
				break
			end
		end
	end
	player2.opponent_force = Vector()

	-- Clipping:
	if(player1.clipbox.Intersects2D(player2.clipbox)) then
		local center1 = player1.clipbox.GetCenter().GetX()
		local center2 = player2.clipbox.GetCenter().GetX()
		local extent1 = player1.clipbox.GetHalfExtents().GetX()
		local extent2 = player2.clipbox.GetHalfExtents().GetX()
		local diff = math.abs(center2 - center1)
		local target_diff = math.abs(extent2 + extent1)
		local offset = (target_diff - diff) * 0.5
		player1.position.SetX(player1.position.GetX() - offset * player1.request_face)
		player2.position.SetX(player2.position.GetX() - offset * player2.request_face)
	end

	-- Facing direction requests:
	if(player1.position.GetX() < player2.position.GetX()) then
		player1.request_face = 1
		player2.request_face = -1
	else
		player1.request_face = -1
		player2.request_face = 1
	end

	-- Camera:
	local CAMERA_HEIGHT = 4 -- camera height from ground
	local DEFAULT_CAMERADISTANCE = -9.5 -- the default camera distance when characters are close to each other
	local MODIFIED_CAMERADISTANCE = -11.5 -- if the two players are far enough from each other, the camera will zoom out to this distance
	local CAMERA_DISTANCE_MODIFIER = 10 -- the required distance between the characters when the camera should zoom out
	local XBOUNDS = 20 -- play area horizontal bounds
	local CAMERA_SIDE_LENGTH = 10 -- play area inside the camera (character can't move outside camera even if inside the play area)

	-- Clamp the players inside the camera:
	local camera_side_left = camera_position.GetX() - CAMERA_SIDE_LENGTH
	local camera_side_right = camera_position.GetX() + CAMERA_SIDE_LENGTH
	player1.position.SetX(math.clamp(player1.position.GetX(), camera_side_left, camera_side_right))
	player2.position.SetX(math.clamp(player2.position.GetX(), camera_side_left, camera_side_right))
	
	local camera_position_new = Vector()
	local distanceX = math.abs(player1.position.GetX() - player2.position.GetX())
	local distanceY = math.abs(player1.position.GetY() - player2.position.GetY())

	-- camera height:
	if(player1.position.GetY() > 4 or player2.position.GetY() > 4) then
		camera_position_new.SetY( math.min(player1.position.GetY(), player2.position.GetY()) + distanceY )
	else
		camera_position_new.SetY(CAMERA_HEIGHT)
	end

	-- camera distance:
	if(distanceX > CAMERA_DISTANCE_MODIFIER) then
		camera_position_new.SetZ(MODIFIED_CAMERADISTANCE)
	else
		camera_position_new.SetZ(DEFAULT_CAMERADISTANCE)
	end

	-- camera horizontal position:
	local centerX = math.clamp((player1.position.GetX() + player2.position.GetX()) * 0.5, -XBOUNDS, XBOUNDS)
	camera_position_new.SetX(centerX)

	-- smooth camera:
	camera_position = vector.Lerp(camera_position, camera_position_new, 0.1)

	-- finally update the global camera with current values:
	camera_transform.ClearTransform()
	camera_transform.Translate(camera_position)
	camera_transform.UpdateTransform()
	GetCamera().TransformCamera(camera_transform)

end

-- ****Main loop:
runProcess(function()

	ClearWorld() -- clears global scene and renderer
	SetProfilerEnabled(false) -- have a bit more screen space
	
	-- Fighting game needs stable frame rate and deterministic controls at all times. We will also refer to frames in this script instead of time units.
	--	We lock the framerate to 60 FPS, so if frame rate goes below, game will play slower
	--	
	--	There is also the possibility to implement game logic in fixed_update() instead, but that is not common for fighting games
	main.SetTargetFrameRate(60)
	main.SetFrameRateLock(true)

	-- We will override the render path so we can invoke the script from Editor and controls won't collide with editor scripts
	--	Also save the active component that we can restore when ESCAPE is pressed
	local prevPath = main.GetActivePath()
	local path = RenderPath3D_TiledForward()
	main.SetActivePath(path)

	local help_text = ""
	help_text = help_text .. "This script is showcasing how to write a simple fighting game."
	help_text = help_text .. "\nControls:\n#####################\nESCAPE key: quit\nR: reload script"
	help_text = help_text .. "\nWASD: move"
	help_text = help_text .. "\nRight: action A"
	help_text = help_text .. "\nUp: action B"
	help_text = help_text .. "\nLeft: action C"
	help_text = help_text .. "\nDown: action D"
	help_text = help_text .. "\nJ: player2 will always jump"
	help_text = help_text .. "\nC: player2 will always crouch"
	help_text = help_text .. "\nI: player2 will be idle"
	help_text = help_text .. "\n\nMovelist:"
	help_text = help_text .. "\n\t A : Light Punch"
	help_text = help_text .. "\n\t B : Heavy Punch"
	help_text = help_text .. "\n\t C : Light Kick"
	help_text = help_text .. "\n\t 6A : Forward Light Punch"
	help_text = help_text .. "\n\t 6C : Heavy Kick"
	help_text = help_text .. "\n\t 2A : Low Punch"
	help_text = help_text .. "\n\t 2B : Uppercut"
	help_text = help_text .. "\n\t 2C : Low Kick"
	help_text = help_text .. "\n\t C : Air Kick (while jumping)"
	help_text = help_text .. "\n\t 2C : Air Heavy Kick (while jumping)"
	help_text = help_text .. "\n\t 623D: Shoryuken"
	help_text = help_text .. "\n\t 236D: Jaunt"
	local font = Font(help_text);
	font.SetSize(20)
	font.SetPos(Vector(10, GetScreenHeight() - 10))
	font.SetAlign(WIFALIGN_LEFT, WIFALIGN_BOTTOM)
	font.SetColor(0xFFADA3FF)
	font.SetShadowColor(Vector(0,0,0,1))
	path.AddFont(font)

	local info = Font("");
	info.SetSize(20)
	info.SetPos(Vector(GetScreenWidth() / 2, GetScreenHeight() * 0.9))
	info.SetAlign(WIFALIGN_LEFT, WIFALIGN_CENTER)
	info.SetShadowColor(Vector(0,0,0,1))
	path.AddFont(info)

	LoadModel("../models/dojo.wiscene")
	
	-- Create the two player characters. Parameters are facing direction and shirt material color to differentiate between them:
	local player1 = Character(1, Vector(1,1,1,1)) -- facing to right, white shirt
	local player2 = Character(-1, Vector(1,0,0,1)) -- facing to left, red shirt
	
	while true do

		ResolveCharacters(player1, player2)

		if(input.Press(string.byte('I'))) then
			player2.ai_state = "Idle"
		elseif(input.Press(string.byte('J'))) then
			player2.ai_state = "Jump"
		elseif(input.Press(string.byte('C'))) then
			player2.ai_state = "Crouch"
		end

		local inputString = "input: "
		for i,element in ipairs(player1.input_buffer) do
			if(element.command ~= "5") then
				inputString = inputString .. element.command
			end
		end
		info.SetText(inputString .. "\nstate = " .. player1.state .. "\nframe = " .. player1.frame)
		
		-- Wait for Engine update tick
		update()
		
	
		if(input.Press(VK_ESCAPE)) then
			-- restore previous component
			--	so if you loaded this script from the editor, you can go back to the editor with ESC
			backlog_post("EXIT")
			killProcesses()
			main.SetActivePath(prevPath)
			return
		end
		if(input.Press(string.byte('R'))) then
			-- reload script
			backlog_post("RELOAD")
			killProcesses()
			main.SetActivePath(prevPath)
			dofile("fighting_game.lua")
			return
		end
		
	end
end)

