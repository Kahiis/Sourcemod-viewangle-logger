# Sourcemod viewangle logger
A Sourcemod plugin for recording player viewangle changes around kills

Heyo, thanks for your interest in this plugin. This plugin was created as a part of my Master's thesis for capturing live, high frequency player viewangles and mouse movement directly from the server in a nonintrusive and handy way(, with hopefully little performance impact).
I went into developing this plugin fairly blind, with little knowledge of modding Source engine games, and thus even less knowledge of SourcePawn. 
As a result, there might be some questionable implementations in the plugin.
Anyhow, many thanks to the SourcePawn and SourceMod community for helping me out while developing this plugin!

Below are a few shortcomings you should be aware, should you decide to use this plugin.
 * It is very likely that this plugin will not work as intended should players leave and join mid match, possibly resulting in recorded traces being mixed and/or overwritten! The PlayerHandler 'object' struct was intended to handle this type of scenario, but was left unfinished.
 * A lot of stuff is hardcoded into the source code itself, such as the save location of traces, weapon restrictions, tick counts etc.
 * The cumulative kill/write value on the filenames is not weapon based, but rather cumulative of total kills by the player.
 * This plugin was developed for CSGO. With CS2 right around the corner, there's no guarantee this plugin will work with CS2

The .sp-file contains the source code for the plugin. The .smx-file is a compiled version of the plugin, and should work by dropping it into your server's sm mod folder.