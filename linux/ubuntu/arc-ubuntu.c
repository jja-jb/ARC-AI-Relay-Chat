#include <gtk/gtk.h>
#include <json-glib/json-glib.h>

typedef struct {
  GtkApplication *application;
  GtkWidget *window;
  GtkWidget *rooms;
  GtkWidget *detail;
  GtkWidget *new_room_name;
  GtkWidget *invite_name;
  gchar *root;
  gchar *admin;
  gchar *arc;
  gchar *room_id;
} ArcUbuntu;

static void show_error(ArcUbuntu *app, const gchar *message) {
  GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(app->window), GTK_DIALOG_MODAL,
      GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", message);
  g_signal_connect(dialog, "response", G_CALLBACK(gtk_window_destroy), NULL);
  gtk_window_present(GTK_WINDOW(dialog));
}

static JsonObject *run_command(ArcUbuntu *app, const gchar *const *suffix) {
  guint count = 0; while (suffix[count]) count++;
  gchar **argv = g_new0(gchar *, count + 5);
  argv[0] = app->admin; argv[1] = "--root"; argv[2] = app->root;
  for (guint i = 0; i < count; i++) argv[i + 3] = (gchar *) suffix[i];
  gchar *stdout_text = NULL, *stderr_text = NULL; gint status = 0; GError *error = NULL;
  gboolean spawned = g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
      &stdout_text, &stderr_text, &status, &error);
  g_free(argv);
  if (!spawned || status != 0) {
    show_error(app, stderr_text && *stderr_text ? stderr_text :
        (stdout_text && *stdout_text ? stdout_text : "ARC administration command failed."));
    g_clear_error(&error); g_free(stdout_text); g_free(stderr_text); return NULL;
  }
  JsonParser *parser = json_parser_new();
  if (!json_parser_load_from_data(parser, stdout_text, -1, &error)) {
    show_error(app, "ARC returned invalid local data.");
    g_clear_error(&error); g_object_unref(parser); g_free(stdout_text); g_free(stderr_text); return NULL;
  }
  JsonNode *root = json_parser_get_root(parser);
  if (!JSON_NODE_HOLDS_OBJECT(root)) { show_error(app, "ARC returned an invalid response."); g_object_unref(parser); g_free(stdout_text); g_free(stderr_text); return NULL; }
  JsonObject *copy = json_object_ref(json_node_get_object(root));
  g_object_unref(parser); g_free(stdout_text); g_free(stderr_text);
  if (!json_object_get_boolean_member_with_default(copy, "ok", FALSE)) {
    JsonObject *failure = json_object_get_object_member(copy, "error");
    show_error(app, failure ? json_object_get_string_member_with_default(failure, "message", "ARC request failed.") : "ARC request failed.");
    json_object_unref(copy); return NULL;
  }
  return copy;
}

static void clear_children(GtkWidget *widget) {
  GtkWidget *child = gtk_widget_get_first_child(widget);
  while (child) { GtkWidget *next = gtk_widget_get_next_sibling(child); gtk_widget_unparent(child); child = next; }
}

static void load_room(ArcUbuntu *app);

static void select_room(GtkListBox *box, GtkListBoxRow *row, gpointer data) {
  ArcUbuntu *app = data; (void)box;
  if (!row) return;
  g_free(app->room_id); app->room_id = g_strdup(g_object_get_data(G_OBJECT(row), "arc-room-id"));
  load_room(app);
}

static void refresh_rooms(ArcUbuntu *app) {
  const gchar *args[] = { "room", "list", NULL };
  JsonObject *response = run_command(app, args); if (!response) return;
  JsonObject *result = json_object_get_object_member(response, "result");
  JsonArray *rooms = json_object_get_array_member(result, "rooms");
  clear_children(app->rooms);
  guint length = rooms ? json_array_get_length(rooms) : 0;
  for (guint i = 0; i < length; i++) {
    JsonObject *room = json_array_get_object_element(rooms, i);
    const gchar *name = json_object_get_string_member_with_default(room, "name", "Untitled room");
    const gchar *id = json_object_get_string_member_with_default(room, "id", "");
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(NULL);
    gchar *text = g_strdup_printf("%s\n<small>%s</small>", name, id);
    gtk_label_set_markup(GTK_LABEL(label), text); gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_widget_set_margin_top(label, 8); gtk_widget_set_margin_bottom(label, 8);
    gtk_widget_set_margin_start(label, 10); gtk_widget_set_margin_end(label, 10);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    g_object_set_data_full(G_OBJECT(row), "arc-room-id", g_strdup(id), g_free);
    gtk_list_box_append(GTK_LIST_BOX(app->rooms), row); g_free(text);
  }
  json_object_unref(response);
}

static void copy_guide(ArcUbuntu *app, JsonObject *invite) {
  JsonObject *participant = json_object_get_object_member(invite, "participant");
  const gchar *binding = json_object_get_string_member_with_default(invite, "binding", "");
  const gchar *id = participant ? json_object_get_string_member_with_default(participant, "id", "") : "";
  if (!*binding || !*id || !app->room_id) { show_error(app, "ARC could not create the AI instructions."); return; }
  gchar *argv[] = { app->arc, "--root", app->root, "guide", "--room", app->room_id,
      "--id", (gchar *)id, "--binding", (gchar *)binding, NULL };
  gchar *out = NULL, *err = NULL; gint status = 0; GError *error = NULL;
  if (!g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, &out, &err, &status, &error) || status != 0) {
    show_error(app, err && *err ? err : "ARC could not create the AI instructions.");
    g_clear_error(&error); g_free(out); g_free(err); return;
  }
  GdkClipboard *clipboard = gtk_widget_get_clipboard(app->window);
  gdk_clipboard_set_text(clipboard, out);
  GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(app->window), GTK_DIALOG_MODAL,
      GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "AI instructions copied to the clipboard.");
  g_signal_connect(dialog, "response", G_CALLBACK(gtk_window_destroy), NULL);
  gtk_window_present(GTK_WINDOW(dialog)); g_free(out); g_free(err);
}

static void invite_ai(GtkButton *button, gpointer data) {
  ArcUbuntu *app = data; (void)button;
  const gchar *name = gtk_editable_get_text(GTK_EDITABLE(app->invite_name));
  if (!app->room_id || !*name) { show_error(app, "Choose a room and enter an AI name."); return; }
  const gchar *args[] = { "participant", "invite", "--room", app->room_id, "--name", name, NULL };
  JsonObject *response = run_command(app, args); if (!response) return;
  copy_guide(app, json_object_get_object_member(response, "result"));
  gtk_editable_set_text(GTK_EDITABLE(app->invite_name), ""); json_object_unref(response); load_room(app);
}

static void retire_ai(GtkButton *button, gpointer data) {
  ArcUbuntu *app = data; const gchar *id = g_object_get_data(G_OBJECT(button), "arc-ai-id");
  if (!app->room_id || !id) return;
  const gchar *args[] = { "participant", "retire", "--room", app->room_id, "--id", id, NULL };
  JsonObject *response = run_command(app, args); if (response) json_object_unref(response); load_room(app);
}

static void create_room(GtkButton *button, gpointer data) {
  ArcUbuntu *app = data; (void)button;
  const gchar *name = gtk_editable_get_text(GTK_EDITABLE(app->new_room_name));
  if (!*name) { show_error(app, "Enter a room name."); return; }
  const gchar *args[] = { "room", "create", "--name", name, NULL };
  JsonObject *response = run_command(app, args); if (!response) return;
  JsonObject *result = json_object_get_object_member(response, "result");
  JsonObject *room = json_object_get_object_member(result, "room");
  g_free(app->room_id); app->room_id = g_strdup(json_object_get_string_member(room, "id"));
  gtk_editable_set_text(GTK_EDITABLE(app->new_room_name), ""); json_object_unref(response);
  refresh_rooms(app); load_room(app);
}

static void append_label(GtkWidget *box, const gchar *text, const gchar *css) {
  GtkWidget *label = gtk_label_new(text); gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  if (css) gtk_widget_add_css_class(label, css); gtk_box_append(GTK_BOX(box), label);
}

static void load_room(ArcUbuntu *app) {
  clear_children(app->detail);
  if (!app->room_id) { append_label(app->detail, "Create or select a room to begin.", "title-2"); return; }
  const gchar *args[] = { "room", "open", "--room", app->room_id, NULL };
  JsonObject *response = run_command(app, args); if (!response) return;
  JsonObject *result = json_object_get_object_member(response, "result");
  JsonObject *room = json_object_get_object_member(result, "room");
  gchar *title = g_strdup_printf("%s", json_object_get_string_member_with_default(room, "name", "ARC room"));
  append_label(app->detail, title, "title-1"); g_free(title);
  gchar *status = g_strdup_printf("%s · %s", app->room_id, json_object_get_string_member_with_default(room, "status", "UNKNOWN"));
  append_label(app->detail, status, "dim-label"); g_free(status);
  GtkWidget *invite = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  app->invite_name = gtk_entry_new(); gtk_entry_set_placeholder_text(GTK_ENTRY(app->invite_name), "AI participant name");
  GtkWidget *invite_button = gtk_button_new_with_label("Invite AI");
  gtk_widget_set_hexpand(app->invite_name, TRUE); gtk_box_append(GTK_BOX(invite), app->invite_name); gtk_box_append(GTK_BOX(invite), invite_button);
  g_signal_connect(invite_button, "clicked", G_CALLBACK(invite_ai), app); gtk_box_append(GTK_BOX(app->detail), invite);
  append_label(app->detail, "Participants", "title-3");
  JsonArray *participants = json_object_get_array_member(result, "participants");
  for (guint i = 0; participants && i < json_array_get_length(participants); i++) {
    JsonObject *participant = json_array_get_object_element(participants, i);
    const gchar *id = json_object_get_string_member_with_default(participant, "id", "");
    gchar *row_text = g_strdup_printf("%s — %s", json_object_get_string_member_with_default(participant, "name", "AI"), json_object_get_string_member_with_default(participant, "phase", "UNKNOWN"));
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); GtkWidget *label = gtk_label_new(row_text);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f); gtk_widget_set_hexpand(label, TRUE); gtk_box_append(GTK_BOX(row), label);
    GtkWidget *retire = gtk_button_new_with_label("Retire"); g_object_set_data_full(G_OBJECT(retire), "arc-ai-id", g_strdup(id), g_free);
    g_signal_connect(retire, "clicked", G_CALLBACK(retire_ai), app); gtk_box_append(GTK_BOX(row), retire); gtk_box_append(GTK_BOX(app->detail), row); g_free(row_text);
  }
  append_label(app->detail, "Open work", "title-3");
  JsonArray *work = json_object_get_array_member(result, "work");
  for (guint i = 0; work && i < json_array_get_length(work); i++) {
    JsonObject *item = json_array_get_object_element(work, i);
    gchar *line = g_strdup_printf("%s — %s", json_object_get_string_member_with_default(item, "owner", ""), json_object_get_string_member_with_default(item, "scope", ""));
    append_label(app->detail, line, NULL); g_free(line);
  }
  json_object_unref(response);
}

static void on_activate(GtkApplication *application, gpointer data) {
  ArcUbuntu *app = data; app->application = application;
  app->window = gtk_application_window_new(application); gtk_window_set_title(GTK_WINDOW(app->window), "ARC — AI Relay Chat"); gtk_window_set_default_size(GTK_WINDOW(app->window), 1080, 700);
  GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12); gtk_widget_set_margin_top(outer, 16); gtk_widget_set_margin_bottom(outer, 16); gtk_widget_set_margin_start(outer, 16); gtk_widget_set_margin_end(outer, 16);
  GtkWidget *new_room = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); app->new_room_name = gtk_entry_new(); gtk_entry_set_placeholder_text(GTK_ENTRY(app->new_room_name), "New room name"); GtkWidget *create = gtk_button_new_with_label("New Room"); gtk_widget_set_hexpand(app->new_room_name, TRUE); gtk_box_append(GTK_BOX(new_room), app->new_room_name); gtk_box_append(GTK_BOX(new_room), create); g_signal_connect(create, "clicked", G_CALLBACK(create_room), app); gtk_box_append(GTK_BOX(outer), new_room);
  GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL); app->rooms = gtk_list_box_new(); gtk_list_box_set_selection_mode(GTK_LIST_BOX(app->rooms), GTK_SELECTION_SINGLE); g_signal_connect(app->rooms, "row-selected", G_CALLBACK(select_room), app);
  GtkWidget *left = gtk_scrolled_window_new(); gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(left), app->rooms); gtk_widget_set_size_request(left, 285, -1);
  GtkWidget *right = gtk_scrolled_window_new(); app->detail = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10); gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(right), app->detail);
  gtk_paned_set_start_child(GTK_PANED(paned), left); gtk_paned_set_end_child(GTK_PANED(paned), right); gtk_widget_set_vexpand(paned, TRUE); gtk_box_append(GTK_BOX(outer), paned);
  gtk_window_set_child(GTK_WINDOW(app->window), outer); refresh_rooms(app); load_room(app); gtk_window_present(GTK_WINDOW(app->window));
}

int main(int argc, char **argv) {
  ArcUbuntu app = {0}; const gchar *data_home = g_get_user_data_dir();
  app.root = g_build_filename(data_home, "arc", NULL);
  app.admin = g_strdup(g_getenv("ARC_ADMIN") ? g_getenv("ARC_ADMIN") : "arc-admin");
  app.arc = g_strdup(g_getenv("ARC_COMMAND") ? g_getenv("ARC_COMMAND") : "arc");
  for (int i = 1; i + 1 < argc; i++) if (g_str_equal(argv[i], "--root")) { g_free(app.root); app.root = g_strdup(argv[++i]); }
  GtkApplication *application = gtk_application_new("org.jonnybass.arc", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(application, "activate", G_CALLBACK(on_activate), &app); int status = g_application_run(G_APPLICATION(application), argc, argv);
  g_object_unref(application); g_free(app.root); g_free(app.admin); g_free(app.arc); g_free(app.room_id); return status;
}
