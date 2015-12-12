config = require "lapis.config"
config.default_config.postgres = {backend: "pgmoon"}
config.reset true

db = require "lapis.db.postgres"
import Model from require "lapis.db.postgres.model"
import stub_queries, assert_queries from require "spec.helpers"

describe "lapis.db.model.relations", ->
  get_queries, mock_query = stub_queries!

  with old = assert_queries
    assert_queries = (expected) ->
      old expected, get_queries!

  local models

  before_each ->
    models = {}
    package.loaded.models = models

  it "should make belongs_to getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    models.CoolUsers = class extends Model
      @primary_key: "user_id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
        {"cool_user", belongs_to: "CoolUsers", key: "owner_id"}
      }

    post = Posts!
    post.user_id = 123
    post.owner_id = 99

    assert post\get_user!
    assert post\get_user!

    post\get_cool_user!

    assert_queries {
      'SELECT * from "users" where "id" = 123 limit 1'
      'SELECT * from "cool_users" where "user_id" = 99 limit 1'
    }

  it "should make belongs_to getter with inheritance", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

      get_user: =>
        with user = super!
          user.color = "green"

    post = Posts!
    post.user_id = 123
    assert.same {
      id: 101
      color: "green"
    }, post\get_user!

  it "caches nil result from belongs_to_fetch", ->
    mock_query "SELECT", {}

    models.Users = class extends Model
      @primary_key: "id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

    post = Posts!
    post.user_id = 123

    assert.same nil, post\get_user!
    assert.same nil, post\get_user!
    assert.same 1, #get_queries!

  it "should make fetch getter", ->
    called = 0

    class Posts extends Model
      @relations: {
        { "thing", fetch: =>
          called += 1
          "yes"
        }
      }

    post = Posts!
    post.user_id = 123

    assert.same "yes", post\get_thing!
    assert.same "yes", post\get_thing!
    assert.same 1, called

    assert_queries {}

  it "should make belongs_to getters for extend syntax", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    m = Model\extend "the_things", {
      relations: {
        {"user", belongs_to: "Users"}
      }
    }

    obj = m!
    obj.user_id = 101


    assert obj\get_user! == obj\get_user!

    assert_queries {
      'SELECT * from "users" where "id" = 101 limit 1'
    }

  it "should make has_one getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class Users extends Model
      @relations: {
        {"user_profile", has_one: "UserProfiles"}
      }

    models.UserProfiles = class UserProfiles extends Model

    user = Users!
    user.id = 123
    user\get_user_profile!

    assert_queries {
      'SELECT * from "user_profiles" where "user_id" = 123 limit 1'
    }

  it "should make has_one getter with custom key", ->
    mock_query "SELECT", { { id: 101 } }

    models.UserData = class extends Model

    models.Users = class Users extends Model
      @relations: {
        {"data", has_one: "UserData", key: "owner_id"}
      }

    user = Users!
    user.id = 123
    assert user\get_data!

    assert_queries {
      'SELECT * from "user_data" where "owner_id" = 123 limit 1'
    }

  it "should make has_many paginated getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Posts = class extends Model
    models.Users = class extends Model
      @relations: {
        {"posts", has_many: "Posts"}
        {"more_posts", has_many: "Posts", where: {color: "blue"}}
      }

    user = models.Users!
    user.id = 1234

    user\get_posts_paginated!\get_page 1
    user\get_posts_paginated!\get_page 2

    user\get_more_posts_paginated!\get_page 2

    user\get_posts_paginated(per_page: 44)\get_page 3

    assert_queries {
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 10 OFFSET 0'
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 10 OFFSET 10'
      {
        [[SELECT * from "posts" where "user_id" = 1234 AND "color" = 'blue' LIMIT 10 OFFSET 10]]
        [[SELECT * from "posts" where "color" = 'blue' AND "user_id" = 1234 LIMIT 10 OFFSET 10]]
      }
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 44 OFFSET 88'
    }


  it "should make has_many getter ", ->
    models.Posts = class extends Model
    models.Users = class extends Model
      @relations: {
        {"posts", has_many: "Posts"}
        {"more_posts", has_many: "Posts", where: {color: "blue"}}
        {"fresh_posts", has_many: "Posts", order: "id desc"}
      }

    user = models.Users!
    user.id = 1234

    user\get_posts!
    user\get_posts!

    user\get_more_posts!
    user\get_fresh_posts!

    assert_queries {
      'SELECT * from "posts" where "user_id" = 1234'
      {
        [[SELECT * from "posts" where "user_id" = 1234 AND "color" = 'blue']]
        [[SELECT * from "posts" where "color" = 'blue' AND "user_id" = 1234]]
      }
      'SELECT * from "posts" where "user_id" = 1234 order by id desc'
    }

  it "should create relations for inheritance", ->
    class Base extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

    class Child extends Base
      @relations: {
        {"category", belongs_to: "Categories"}
      }

    assert Child.get_user, "expecting get_user"
    assert Child.get_category, "expecting get_category"
    assert.same nil, rawget Child, "get_user"

  describe "polymorphic belongs to", ->
    local Foos, Bars, Bazs, Items

    before_each ->
      models.Foos = class Foos extends Model
      models.Bars = class Bars extends Model
      models.Bazs = class Bazs extends Model

      Items = class Items extends Model
        @relations: {
          {"object", polymorphic_belongs_to: {
            [1]: {"foo", "Foos"}
            [2]: {"bar", "Bars"}
            [3]: {"baz", "Bazs"}
          }}
        }

    it "should model_for_object_type", ->
      assert Foos == Items\model_for_object_type 1
      assert Foos == Items\model_for_object_type "foo"

      assert Bars == Items\model_for_object_type 2
      assert Bars == Items\model_for_object_type "bar"

      assert Bazs == Items\model_for_object_type 3
      assert Bazs == Items\model_for_object_type "baz"

      assert.has_error ->
        Items\model_for_object_type 4

      assert.has_error ->
        Items\model_for_object_type "bun"

    it "should object_type_for_model", ->
      assert.same 1, Items\object_type_for_model Foos
      assert.same 2, Items\object_type_for_model Bars
      assert.same 3, Items\object_type_for_model Bazs

      assert.has_error ->
        Items\object_type_for_model Items

    it "should object_type_for_object", ->
      assert.same 1, Items\object_type_for_object Foos!
      assert.same 2, Items\object_type_for_object Bars!
      assert.same 3, Items\object_type_for_object Bazs

      assert.has_error ->
        Items\object_type_for_model {}

    it "should call getter", ->
      mock_query "SELECT", { { id: 101 } }

      for i, {type_id, cls} in ipairs {{1, Foos}, {2, Bars}, {3, Bazs}}
        item = Items\load {
          object_type: type_id
          object_id: i * 33
        }

        obj = item\get_object!

        obj.__class == cls

        obj2 = item\get_object!

        assert.same obj, obj2

      assert_queries {
        'SELECT * from "foos" where "id" = 33 limit 1'
        'SELECT * from "bars" where "id" = 66 limit 1'
        'SELECT * from "bazs" where "id" = 99 limit 1'
      }


    it "should call preload with empty", ->
      Items\preload_objects {}

      assert_queries {
      }

    it "should call preload", ->
      k = 0
      n = ->
        k += 1
        k

      items = {
        Items\load {
          object_type: 1
          object_id: n!
        }

        Items\load {
          object_type: 2
          object_id: n!
        }

        Items\load {
          object_type: 1
          object_id: n!
        }

        Items\load {
          object_type: 1
          object_id: n!
        }
      }

      Items\preload_objects items

      assert_queries {
        'SELECT * from "foos" where "id" in (1, 3, 4)'
        'SELECT * from "bars" where "id" in (2)'
      }

    it "preloads with fields", ->
      items = {
        Items\load {
          object_type: 1
          object_id: 111
        }

        Items\load {
          object_type: 2
          object_id: 112
        }

        Items\load {
          object_type: 3
          object_id: 113
        }
      }

      Items\preload_objects items, fields: {
        bar: "a, b"
        baz: "c, d"
      }

      assert_queries {
        'SELECT * from "foos" where "id" in (111)'
        'SELECT a, b from "bars" where "id" in (112)'
        'SELECT c, d from "bazs" where "id" in (113)'
      }

  it "should find relation", ->
    import find_relation from require "lapis.db.model.relations"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
        {"cool_user", belongs_to: "CoolUsers", key: "owner_id"}
      }

    class BetterPosts extends Posts
      @relations: {
        {"tags", has_many: "Tags"}
      }

    assert.same {"user", belongs_to: "Users"}, (find_relation Posts, "user")
    assert.same nil, (find_relation Posts, "not there")
    assert.same {"cool_user", belongs_to: "CoolUsers", key: "owner_id"},
      (find_relation BetterPosts, "cool_user")
