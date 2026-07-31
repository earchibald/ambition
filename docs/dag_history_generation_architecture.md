DAG History Generation Architecture

Target Audience: Lead Coding Agent / Systems Architect
Context: This document outlines the algorithm and data structure for generating a plausible, complex history for "The Living Delve." This generation occurs at the start of a new game and produces the initial state of the world, village, and dungeon floors.

1. The Core Concept: History as a Graph

Instead of generating history purely through a linear timeline or random tables, we model history as a Directed Acyclic Graph (DAG).

Nodes: Represent Entities (e.g., Kingdoms, Factions, Specific Leaders, Legendary Artifacts, Dungeon Floors, Surface Villages).

Edges: Represent Events (e.g., "Founded By," "Conquered By," "Destroyed By," "Forged By," "Migrated To"). Edges are directed, moving forward in time from cause to effect.

Acyclic: Time only flows in one direction. An event cannot cause an event in the past.

This structure allows us to easily trace causality. If the player finds a "Rusted Goblin Sword" on Floor 4, the DAG can trace back: Sword -> Forged By (Goblin Faction A) -> Resided On (Floor 4) -> Destroyed By (Fungal Spore-Lord).

2. The Generation Algorithm (The "World Gen Tick")

The world generation process simulates hundreds of years in discrete "Epochs" (abstracted chunks of time, e.g., decades).

Step 1: Initial Seeding

Generate a set of "Root Nodes" representing primordial entities (e.g., The World Itself, The Deep Caverns, Ancient Gods, First Civilizations).

Define the physical boundaries: Total number of dungeon floors, existence of a surface region, basic biomes for each floor (determined via procedural noise, e.g., Perlin noise for humidity/temperature mapping to biomes).

Step 2: The Epoch Loop

The algorithm iterates through a set number of epochs (e.g., 50 epochs representing 500 years). During each epoch:

Node Evaluation: Iterate through all Active Nodes (entities currently alive/existing).

Event Generation: For each Active Node, roll against its internal logic (or a set of randomized tables weighted by the node's properties) to determine if it initiates an Event.

Example: A "Dwarven Kingdom" node checks its "Expansionism" stat. If it rolls high, it generates an "Expands To" event targeting an empty or weakly defended Dungeon Floor node.

Edge Creation & State Resolution: If an event occurs, create a directed Edge linking the source node to the target node. Update the state of the nodes involved.

Example: [Dwarven Kingdom] --(Expands To)--> [Floor 3].

Floor 3's state changes from "Empty Cavern" to "Dwarven Outpost." A new node is created for the outpost faction.

Conflict Resolution: If multiple nodes target the same resource/floor, resolve the conflict (e.g., combat math based on abstracted military strength). Create "War," "Conquest," or "Defeat" edges.

Deactivation: If a node's population/strength drops below a threshold, it becomes Inactive (ruined, dead, lost).

Step 3: Pruning and Optimization

After the final epoch, prune nodes that have no relevance to the current game state (e.g., a faction that existed in Epoch 1 and left no ruins, artifacts, or descendants).

3. Data Structures

The coding agent should implement the DAG using efficient graph representation (e.g., adjacency lists).

Node Data Model (Abstract Base):

NodeID: Unique Integer/UUID.

NodeType: Enum (Faction, Leader, Location, Artifact, Event_Abstract).

Status: Enum (Active, Inactive).

BirthEpoch: Integer.

Tags: List

$$String$$

 (e.g., "Militaristic", "Fungal", "Underground").

Edge Data Model:

SourceNodeID: ID of the initiating entity.

TargetNodeID: ID of the receiving entity.

EdgeType: Enum (Founded, Destroyed, Migrated_To, Forged, Allied_With).

Epoch: When the event occurred.

ContextData: Dictionary (e.g., {"Casualties": 500, "Stolen_Wealth": 1000}).

4. Translating DAG to Game State

The DAG is an abstract history. When the player starts the game, the system must translate the current state of the DAG (the Active Nodes and their recent history) into the ECS Data Layer.

Map Generation: Look at the Active Location nodes. If Floor 4 is currently occupied by a "Fungal Faction" but has a history edge showing it was once a "Dwarven Foundry," the map generator selects a "Dwarven Ruin" tileset and overlays it with "Fungal Spore" hazards.

ECS Population: Active Faction nodes are translated into Tier 1 (Abstracted) or Tier 2 (Simulated) entities in the ECS, as defined in the ECS architecture spec.

Artifact Placement: Active Artifact nodes are placed into the inventories of Active Faction Leaders or hidden in ruins on specific floors.

Village State: The Surface Village node is evaluated. Its current wealth, population, and available merchants are derived from its recent historical trading/conflict edges.

5. Gray Box Integration

During the Epoch Loop, the system occasionally queries abstract "Outside World" nodes.

Surface Empire Node: Periodically pushes "Migration" or "Trade" events to the Surface Village node.

The Deep Roads Node: Periodically pushes "Invasion" or "Emergence" events to the lowest Dungeon Floor nodes.
This prevents stagnation during history generation and establishes the pathways for the gray box systems that will run during active gameplay.
