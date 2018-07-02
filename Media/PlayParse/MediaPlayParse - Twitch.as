﻿/*
	Twitch media parse
*/	

//	string GetTitle() 									-> get title for UI
//	string GetVersion									-> get version for manage
//	string GetDesc()									-> get detail information
//	string GetLoginTitle()								-> get title for login dialog
//	string GetLoginDesc()								-> get desc for login dialog
//	string ServerCheck(string User, string Pass) 		-> server check
//	string ServerLogin(string User, string Pass) 		-> login
//	void ServerLogout() 								-> logout
// 	bool PlayitemCheck(const string &in)				-> check playitem
//	array<dictionary> PlayitemParse(const string &in)	-> parse playitem
// 	bool PlaylistCheck(const string &in)				-> check playlist
//	array<dictionary> PlaylistParse(const string &in)	-> parse playlist

string GetTitle() {
	return "Twitch";
}

string GetVersion() {
	return "1";
}

string GetDesc() {
	return "https://twitch.tv/";
}

class QualityListItem {
	string url;
	string quality;
	string qualityDetail;
	string resolution;
	string bitrate;
	string format;
	int itag = 0;
	double fps = 0.0;
	int type3D = 0; // 1:sbs, 2:t&b
	bool is360 = false;

	dictionary toDictionary() {
		dictionary ret;
		
		ret["url"] = url;
		ret["quality"] = quality;
		ret["qualityDetail"] = qualityDetail;
		ret["resolution"] = resolution;
		ret["bitrate"] = bitrate;
		ret["format"] = format;
		ret["itag"] = itag;
		ret["fps"] = fps;
		ret["type3D"] = type3D;
		ret["is360"] = is360;
		return ret;
	}	
};

int GetITag(const string &in qualityName) {
	array<string> qualities = {"audio_only", "160p", "360p", "480p", "720p", "720p60", "1080p", "1080p60"};
	qualities.reverse();
	if (qualityName.find("(source)") > 0) {
		return 1;
	}
	int indexQuality = qualities.find(qualityName);
	if (indexQuality > 0) {
		return indexQuality + 2;
	} else {
		return -1;
	}
}

bool PlayitemCheck(const string &in path) {
	if (path.find("://twitch.tv") >= 0) {
		return true;
	}
	if (path.find("://www.twitch.tv") >= 0) {
		return true;
	}
	if (path.find("://clips.twitch.tv") >= 0) {
		return true;
	}
	return false;
}

string ClipsParse(const string &in path, dictionary &MetaData, array<dictionary> &QualityList, const string &in headerClientId) {
	string clipId = HostRegExpParse(path, "clips.twitch.tv/([-a-zA-Z0-9_]+)");
	string clipApi = "https://clips.twitch.tv/api/v2/clips/" + clipId + "/status";
	string clipStatusApi = "https://api.twitch.tv/kraken/clips/" + clipId;

	string jsonClip = HostUrlGetString(clipApi, "", "");
	string jsonStatusClip = HostUrlGetString(clipStatusApi, "", headerClientId + "\naccept: application/vnd.twitchtv.v5+json");

	HostPrintUTF8(jsonStatusClip);
	JsonReader ClipReader;
	JsonValue ClipRoot;

	string srcBestUrl = "";
	if (ClipReader.parse(jsonClip, ClipRoot) && ClipRoot.isObject()) {
		JsonValue qualityArray;
		if (ClipRoot["quality_options"].isArray()) {
			qualityArray = ClipRoot["quality_options"];
		} else {
			return "";
		}

		srcBestUrl = qualityArray[0]["source"].asString();

		if (@QualityList !is null) {
			for (int k = 0; k < qualityArray.size(); k++) {
				string currentQualityUrl = qualityArray[k]["source"].asString();
				string qualityName = qualityArray[k]["quality"].asString() + "p";

				QualityListItem qualityItem;
				qualityItem.itag = k;
				qualityItem.quality = qualityName;
				qualityItem.qualityDetail = qualityName;
				qualityItem.url = currentQualityUrl;
				QualityList.insertLast(qualityItem.toDictionary());
			}
		}
	}

	string titleClip;
	string game;
	string display_name;
	string views;
	string created_at;
	JsonReader StatusClipReader;
	JsonValue StatusClipRoot;
	if (StatusClipReader.parse(jsonStatusClip, StatusClipRoot) && StatusClipRoot.isObject()) {
		titleClip = StatusClipRoot["title"].asString();
		game = StatusClipRoot["game"].asString();
		views = "Views: " + StatusClipRoot["views"].asString();
		created_at = HostRegExpParse(StatusClipRoot["created_at"].asString(), "([0-9-]+)T");
		display_name = StatusClipRoot["broadcaster"]["display_name"].asString();
	}

	MetaData["title"] = titleClip;
	MetaData["content"] = titleClip + " | " + game + " | " + display_name + " | " + views + " | " + created_at;

	return srcBestUrl;
}

string PlayitemParse(const string &in path, dictionary &MetaData, array<dictionary> &QualityList) {

	// Any twitch API demands client id in header.
	string headerClientId = "Client-ID: 1dviqtp3q3aq68tyvj116mezs3zfdml";

	bool isVod = false;
	bool isClip = false;
	if (path.find("twitch.tv/videos/") > 0) {
		isVod = true;
	}
	string clipId = HostRegExpParse(path, "clips.twitch.tv/([-a-zA-Z0-9_]+)");
	HostPrintUTF8(clipId);
	if (path.find("clips.twitch.tv") >= 0) {
		return ClipsParse(path, MetaData, QualityList, headerClientId);
	}
	

	string nickname = HostRegExpParse(path, "https://twitch.tv/([-a-zA-Z0-9_]+)");
	if (nickname == "") {
		nickname = HostRegExpParse(path, "https://www.twitch.tv/([-a-zA-Z0-9_]+)");
	}

	string vodId = "";
	if (isVod) {
		vodId = HostRegExpParse(path, "twitch.tv/videos/([0-9]+)");
	}
	HostPrintUTF8(vodId);
// 	https://usher.ttvnw.net/vod/
//  https://api.twitch.tv/api/vods/

	// Firstly we need to request for api to get pretty weirdly token and sig.
	string tokenApi = "https://api.twitch.tv/api/channels/" + nickname + "/access_token?need_https=true";
	if (isVod) {
		tokenApi = "https://api.twitch.tv/api/vods/" + vodId + "/access_token?need_https=true";
	}
	// Parameter p should be random number.
	string m3u8Api = "https://usher.ttvnw.net/api/channel/hls/" + nickname + ".m3u8?allow_source=true&p=7278365player_backend=mediaplayer&playlist_include_framerate=true&allow_audio_only=true";
	if (isVod) {
		m3u8Api = "https://usher.ttvnw.net/vod/" + vodId + ".m3u8?allow_source=true&p=7278365player_backend=mediaplayer&playlist_include_framerate=true&allow_audio_only=true";
	}
	// &sig={token_sig}&token={token}
	string jsonToken = HostUrlGetString(tokenApi, "", headerClientId);

	// Get information of current stream.
	// string idChannel = HostRegExpParse(jsonToken, ":([0-9]+)");
	string jsonChannelStatus = "";
	if (!isVod) {
		jsonChannelStatus = HostUrlGetString("https://api.twitch.tv/kraken/channels/" + nickname, "", headerClientId);
	} else {
		jsonChannelStatus = HostUrlGetString("https://api.twitch.tv/kraken/videos/v" + vodId, "", headerClientId);
	}
	string titleStream;
	string game;
	string display_name;
	JsonReader StatusChannelReader;
	JsonValue StatusChannelRoot;
	if (StatusChannelReader.parse(jsonChannelStatus, StatusChannelRoot) && StatusChannelRoot.isObject()) {
		if (!isVod) {
			titleStream = StatusChannelRoot["status"].asString();
		} else {
			titleStream = StatusChannelRoot["title"].asString();
		}
		game = StatusChannelRoot["game"].asString();
		if (!isVod) {
			display_name = StatusChannelRoot["display_name"].asString();
		} else {
			display_name = StatusChannelRoot["channel"]["display_name"].asString();
		}
	}

	// Read weird token and sig.
	string sig;
	string token;
	JsonReader TokenReader;
	JsonValue TokenRoot;
	if (TokenReader.parse(jsonToken, TokenRoot) && TokenRoot.isObject()) {
		sig = "&sig=" + TokenRoot["sig"].asString();
		token = "&token=" + TokenRoot["token"].asString();
	}

	// Second request to get list of *.m3u8 urls.
	string jsonM3u8 = HostUrlGetString(m3u8Api + sig + token, "", headerClientId);
	jsonM3u8.replace('"', "");
	HostPrintUTF8(jsonM3u8);	


	string m3 = ".m3u8";

	string sourceQualityUrl = "https://" + HostRegExpParse(jsonM3u8, "https://([a-zA-Z-_.0-9/]+)" + m3) + m3;

	if (@QualityList !is null) {
		array<string> arrayOfM3u8 = jsonM3u8.split("#EXT-X-MEDIA:");
		for (int k = 1, len = arrayOfM3u8.size(); k < len; k++) {
			string currentM3u8 = arrayOfM3u8[k];
			string currentQuality = HostRegExpParse(currentM3u8, "NAME=([a-zA-Z-_.0-9/ ()]+)");
			string currentQualityUrl = "https://" + HostRegExpParse(currentM3u8, "https://([a-zA-Z-_.0-9/]+)" + m3) + m3;

			QualityListItem qualityItem;
			qualityItem.itag = GetITag(currentQuality);
			qualityItem.quality = currentQuality;
			qualityItem.qualityDetail = currentQuality;
			qualityItem.url = currentQualityUrl;
			QualityList.insertLast(qualityItem.toDictionary());
		}
	}


	MetaData["title"] = titleStream;
	MetaData["content"] = "— " + titleStream + " | " + game;
	// TODO check every N seconds viewers.
	// MetaData["viewCount"] = "195";
	MetaData["author"] = display_name;
	MetaData["chatUrl"] = "https://zik.one/chat/?theme=bttv_dark&channel=" + nickname + "&fade=false&bot_activity=false&prevent_clipping=false";
	return sourceQualityUrl;
}