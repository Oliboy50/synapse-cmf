project_name = synapse
APPS = $(shell ls bin | grep console | sed s/console_//g)

#
# Dev environment
#
init: vm-up vm-ssh

vm-ssh:
	vagrant ssh

vm-up:
	vagrant up

vm-halt:
	vagrant halt

vm-provision:
	vagrant up --no-provision
	vagrant provision

vm-destroy:
	vagrant destroy

vm-rebuild: vm-destroy vm-provision

#
# Main tasks
#
install: install-infra install-vendors install-database clean

build: build-database

update: update-composer update-database

#
# Install
#
install-npm:
	npm install
install-composer: bin/composer
	./bin/composer install
install-local-parameters:
	$(foreach app,$(APPS),cp -n apps/$(app)/config/parameters.yml.dist apps/$(app)/config/parameters.yml;)
install-directories:
	$(foreach app,$(APPS),mkdir -p web/assets/$(app);)

install-vendors: install-composer install-local-parameters

#
# Directories & files
#
bin/composer:
	curl -sS https://getcomposer.org/installer | php -- --install-dir=bin --filename=composer
	chmod +x bin/composer || /bin/true
bin/php-cs-fixer:
	wget http://get.sensiolabs.org/php-cs-fixer.phar -O bin/php-cs-fixer
	chmod +x bin/php-cs-fixer || /bin/true
bin/phpunit:
	ln -fs ../vendor/phpunit/phpunit/phpunit bin/phpunit
wallet:
	mkdir -p wallet
update-bin: bin/composer bin/php-cs-fixer
	./bin/composer self-update
	php bin/php-cs-fixer self-update
.git/hooks/pre-commit:
	curl https://raw.githubusercontent.com/LinkValue/symfony-git-hooks/master/pre-commit -o .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit || /bin/true

install-infra: wallet update-bin .git/hooks/pre-commit

#
# Database
#
install-database:
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:database:create --if-not-exists;)
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:migrations:migrate -n --allow-no-migration;)

build-database: install-database
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:fixtures:load -n;)
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:fixtures:load -n --em="synapse";)

update-database: install-database
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:schema:validate || test "$$?" -gt 1;)
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:migrations:diff --filter-expression="/^$(app)/";)
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:migrations:diff --filter-expression="/^synapse_.+/" --em=synapse;)
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:migrations:migrate -n;)

trash-database:
	$(foreach app,$(APPS),php bin/console_$(app) doctrine:database:drop --force --if-exists;)
	rm -rf web/assets/* || /bin/true

trash-uncommitted-migrations:
	$(foreach app,$(APPS),git status apps/$(app)/DoctrineMigrations --porcelain | grep "??" | sed "s/?? //g" | xargs -I {} rm {};)

squash-migrations: trash-uncommitted-migrations trash-database update-database

rebuild-database: trash-database build-database

#
# Clean
#
clean: bin/composer
	rm -rf vendor/composer/autoload*  || /bin/true
	rm var/bootstrap.php.cache || /bin/true
	rm -rf web/bundles || /bin/true
	./bin/composer dump-autoload
	./bin/composer run-script setup-bootstrap -vv
	rm -rf var/cache/$(project_name) || /bin/true
	rm -rf var/logs/$(project_name) || /bin/true
	test -d /dev/shm/$(project_name) && rm -rf /dev/shm/$(project_name) || /bin/true
	$(foreach app,$(APPS),php bin/console_$(app) cache:warmup;)
	$(foreach app,$(APPS),php bin/console_$(app) cache:warmup --env=prod;)
	$(foreach app,$(APPS),php bin/console_$(app) assets:install --symlink;)

#
# Update
#
update-composer: bin/composer
	./bin/composer update --no-scripts

#
# Git
#
push-subrepo:
	git subrepo push src/Synapse/Cmf
	git subrepo push src/Synapse/Admin
	git subrepo push src/Synapse/Page
	git subrepo push src/Synapse/Demo

#
# Tests
#
tests: bin/phpunit
	./bin/phpunit -c . --testsuite synapse_cmf
tests-covered: bin/phpunit
	rm -rf web/coverage || true
	php -dzend_extension=xdebug.so bin/phpunit -c phpunit.xml.dist --testsuite synapse_cmf --coverage-html web/coverage
	@echo "\nCoverage report : \n\033[1;32m http://tests.synapse.dev/coverage/index.html\033[0m\n"

#
# CI
#
ci-install-composer: bin/composer
	./bin/composer install --prefer-dist
bin/ocular:
	wget https://scrutinizer-ci.com/ocular.phar -O bin/ocular
	chmod +x bin/ocular || /bin/true

travis: ci-install-composer bin/ocular
	./vendor/phpunit/phpunit/phpunit src -c phpunit.xml.dist --testsuite synapse_cmf --coverage-clover=coverage.clover
	(test -f coverage.clover && php bin/ocular code-coverage:upload --format=php-clover coverage.clover) || true

